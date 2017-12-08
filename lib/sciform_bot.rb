require 'telegram/bot'
require 'yaml'
require 'html_to_plain_text'
require 'rest-client'

$commands = Telegram::Bot::Types::ReplyKeyboardMarkup.new(resize_keyboard: true,
	keyboard: [['/pagine']])

def send_message(chat, text, keyboard = false)
	if !chat.permit
		$bot.api.send_message(chat_id: chat.chat_id, text: "Questa chat non e' autorizzata!")
		return
	end

	begin
		$bot.api.send_message(chat_id: chat.chat_id, reply_markup: (keyboard ? $commands : nil), parse_mode: 'Markdown', text: text)
	rescue Telegram::Bot::Exceptions::ResponseError => e
		$bot.logger.info("The chat #{chat.ref} is no longer responding. Removing.")
		$bot.logger.debug("Chat reported: #{e}")
		chat.delete
	end
end 

def process_start(chat)
	text = "Ciao, io sono il bot SciForm. "
	text << "Ti informero' su modifiche alle mie pagine monitorate. Solo gli utenti autorizzati "
	text << "possono accedere ai miei servizi. Devi mandarmi il tuo numero per ricevere le mie "
	text << "notifiche, cosi' posso verificare se sei autorizzato."
	send_message(chat, text)
end

def process_help(chat)
	send_message(chat, "Io monitoro alcune pagine di sciform e ti avviso se ci sono modifiche." +
		" usa il comando /pagine per vedere quali pagine sto monitorando.")
end

def process_pages(chat)
	text = "Le mie pagine monitorate sono:\n\n"

	Page.find_each do |page,i|
		text << "[#{page.label}](#{page.url})\n"
	end

	send_message(chat, text)
end

def process_hello(chat)
	send_message(chat, "Ciao \u{1F603}", true)
end

def telegram_loop
	token = '469458692:AAGXSGyzD2Bo7KjOTEG-GtcmP6Ci8mZMCeo'
	$bot = Telegram::Bot::Client.new(token, logger: Logger.new(STDOUT))
	$bot.options[:timeout] = 3

	$bot.listen do |message|
		chat = Chat.find_or_create_by(Chat.adapt(message.chat))

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
	Chat.find_each do |chat|
		begin
			$bot.api.send_chat_action(chat_id: chat.chat_id, action: action.to_s)
		rescue Telegram::Bot::Exceptions::ResponseError
			$bot.logger.info("The chat #{chat.inspect} is no longer responding. Removing.")
			chats.delete
		end
	end
end 

def get_page_md5(page)
	html = RestClient.get(page.url)
	Digest::MD5.hexdigest(HtmlToPlainText.plain_text(html))
end 

def notify_users(page)
	Chat.where(permit: true).each do |chat|
		$bot.logger.debug("Notify chat #{chat.chat_id} (#{chat.ref})")
		send_message(chat, "La pagina [#{page.label}](#{page.url}) e' cambiata.")
	end
end

def send_admin_message
	filename = "admin.txt"
	return if !File.exists? filename
	text = File.read(filename)
	Chat.where(permit: true).each do |chat|
		$bot.logger.info("Sending admin message to #{chat.ref}")
		send_message(chat, text)
	end
	FileUtils.rm(filename)
end

def pages_loop
	minute = 60
	while true
		next if !$bot
		Page.find_each do |page|
			send_chats_action(:typing)
			$bot.logger.debug("Checking #{page['label']}")
			md5 = get_page_md5(page)
			case
			when !page.md5
				$bot.logger.debug("No md5 for page #{page.label}, saving.")
				page.md5 = md5
				page.save
			when md5 != page.md5
				$bot.logger.debug("Page #{page.label} has changed. (#{md5} vs #{page.md5}")
				page.md5 = md5
				page.save	
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