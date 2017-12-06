require 'telegram/bot'
require 'yaml'
require 'html_to_plain_text'
require 'rest-client'

CHATSFILE = 'chatsfile.yml'
PAGESFILE = 'pagesfile.yml'

def load_chats
	$chats = YAML.load_file(CHATSFILE)
	if $chats
		$bot.logger.info("Chats loaded: #{$chats.map{|id,chat| "#{id}-#{chat[:title]}"}}")
	else
		$chats = {}
	end
end

def save_chats
	File.write(CHATSFILE, $chats.to_yaml)
end

$commands = Telegram::Bot::Types::ReplyKeyboardMarkup.new(resize_keyboard: true,
	keyboard: [['/pagine']])

def send_message(chat_id, text)
	if !$chats.dig(chat_id, :permit)
		$bot.api.send_message(chat_id: chat_id, text: "Questa chat non e' autorizzata!")
		return
	end

	begin
		$bot.api.send_message(chat_id: chat_id, reply_markup: $commands, parse_mode: 'Markdown', text: text)
	rescue Telegram::Bot::Exceptions::ResponseError => e
		$bot.logger.info("The chat #{chat_id} is no longer responding. Removing.")
		$bot.logger.debug("Chat reported: #{e}")
		$chats.delete(chat_id)
		save_chats
	end
end 

def process_start(chat)
	text = "Ciao, io sono il bot SciForm. "
	text << "Ti informero' su modifiche alle mie pagine monitorate. Solo gli utenti autorizzati "
	text << "possono accedere ai miei servizi. Devi mandarmi il tuo numero per ricevere le mie "
	text << "notifiche, cosi' posso verificare se sei autorizzato."
	send_message(chat.id, text)
end

def process_help(chat)
	send_message(chat.id, "Io monitoro alcune pagine di sciform e ti avviso se ci sono modifiche." +
		" usa il comando /pagine per vedere quali pagine sto monitorando.")
end

def process_pages(chat)
	return if !$pages
	text = "Le mie pagine monitorate sono:\n\n"

	$pages.each_with_index do |page,i|
		text << "#{i}) [#{page['label']}](#{page['url']})\n"
	end

	send_message(chat.id, text)
end

def process_hello(chat)
	send_message(chat.id, "Ciao :-)")
end

def telegram_loop
	token = '469458692:AAGXSGyzD2Bo7KjOTEG-GtcmP6Ci8mZMCeo'
	$bot = Telegram::Bot::Client.new(token, logger: Logger.new(STDOUT))
	$bot.options[:timeout] = 3

	load_chats

	$bot.listen do |message|
		chat = message.chat

		if !$chats[chat.id]
			$chats[chat.id] = chat.to_h 
			save_chats
		end

		case
		when !message.text
		when message.text == '/start'
			process_start(chat)
		when message.text == '/aiuto' || message.text.downcase == 'aiuto'
			process_help(chat)
		when message.text == '/pagine' || message.text.downcase == 'pagine'
			process_pages(chat)
		when message.text.include?('sciformbot')
			process_hello(chat)
		end
	end
end

def send_chats_action(action)
	return if !$chats
	$chats.each_pair do |chat_id, data|
		begin
			$bot.api.send_chat_action(chat_id: chat_id, action: action.to_s)
		rescue Telegram::Bot::Exceptions::ResponseError
			$bot.logger.info("The user #{data['user']} is no longer responding. Removing.")
			$chats.delete(chat_id)
			save_chats
		end
	end
end 

def load_pages
	$pages = YAML.load_file(PAGESFILE)
end

def save_pages
	File.write(PAGESFILE, $pages.to_yaml)
end

def get_page_md5(page)
	html = RestClient.get(page['url'])
	Digest::MD5.hexdigest(HtmlToPlainText.plain_text(html))
end 

def notify_users(page)
	$chats.keys.each do |chat_id|
		$bot.logger.debug("Notify #{chat_id}")
		send_message(chat_id, "La pagina [#{page['label']}](#{page['url']}) e' cambiata.")
	end
end

def send_admin_message
	return if !$chats
	Dir.glob("*.admin").each do |file|
		text = File.read(file)
		$chats.each do |chat_id,chat|
			$bot.logger.info("Sending content of #{file} to #{chat['name']}")
			send_message(chat_id, text)
		end
		FileUtils.rm(file)
	end
end

def pages_loop
	load_pages
	minute = 60
	while true
		next if !$bot
		$pages.each do |page|
			send_chats_action(:typing)
			$bot.logger.debug("Checking #{page['label']}")
			md5 = get_page_md5(page)
			case
			when !page['md5']
				$bot.logger.debug("No md5 for page #{page['label']}, saving.")
				page['md5'] = md5
				save_pages
			when md5 != page['md5']
				$bot.logger.debug("Page #{page['label']} haas changed.")
				page['md5'] = md5
				save_pages	
				notify_users(page)
			end 
		end
		sleep ENV['SLEEP_TIME'] ? ENV['SLEEP_TIME'].to_i : 20 * minute
	end
end

def log_lines(lines)
	return if !$bot
	lines.each do |line|
		$bot.logger.debug(line)
	end
end

threads = []
threads << Thread.new do
	while true
		begin
			telegram_loop
		rescue => e
			$bot.logger.error("Error in telegram loop: #{e}")
			log_lines(e.backtrace)
		end
	end
end
threads << Thread.new do
	while true
		begin
			pages_loop
		rescue => e
			$bot.logger.error("Error in pages loop: #{e}")
			log_lines(e.backtrace)
		end
	end
end
threads << Thread.new do
	while true
		begin
			send_admin_message
			sleep 5
		rescue => e
			$bot.logger.error("Error in admin message loop: #{e}")
			log_lines(e.backtrace)
		end
	end
end
threads.each { |thr| thr.join }
