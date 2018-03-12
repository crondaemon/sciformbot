require 'telegram/bot'
require 'yaml'
require 'html_to_plain_text'
require 'rest-client'

$commands = Telegram::Bot::Types::ReplyKeyboardMarkup.new(resize_keyboard: true,
	keyboard: [['/pagine']])

$remove_kb = Telegram::Bot::Types::ReplyKeyboardRemove.new(remove_keyboard: true)

def send_message(chat, text, keyboard = false)
	if !chat.permit
		$bot.api.send_message(chat_id: chat.chat_id, text: "Questa chat non e' autorizzata!")
		return
	end

	begin
		$bot.api.send_message(chat_id: chat.chat_id, reply_markup: $remove_kb, parse_mode: 'Markdown',
			text: text, disable_web_page_preview: true)
	rescue Telegram::Bot::Exceptions::ResponseError => e
		$bot.logger.info("The chat #{chat.ref} is no longer responding. Removing.")
		$bot.logger.debug("Chat error: #{e}")
	end
end 

def process_start(chat)
	text = "Ciao, io sono il bot SciForm. "
	text << "Ti informero' su modifiche alle mie pagine monitorate. Solo gli utenti autorizzati "
	text << "possono accedere ai miei servizi."
	send_message(chat, text)
end

def process_help(chat)
	send_message(chat, "Io monitoro alcune pagine di sciform e ti avviso se ci sono modifiche." +
		" usa il comando /pagine per vedere quali pagine sto monitorando.")
end

def process_pages(chat)
	text = "Le mie pagine monitorate sono:\n\n"

	Page.find_each do |page,i|
		text << "- [#{page.label}](#{page.url})\n"
	end

	send_message(chat, text)
end

def process_hello(chat)
	send_message(chat, "Ciao \u{1F603}", true)
end

def telegram_loop
	token = '469458692:AAGXSGyzD2Bo7KjOTEG-GtcmP6Ci8mZMCeo'
	$bot = Telegram::Bot::Client.new(token, logger: Logger.new(STDOUT))
	if ENV['LOG_LEVEL']
		$bot.logger.info("Changing logging level to #{ENV['LOG_LEVEL']}")
		Rails.logger.level = ENV['LOG_LEVEL'].to_sym
		$bot.logger.level = "Logger::#{ENV['LOG_LEVEL']}".constantize
	end
	$bot.options[:timeout] = 3

	$bot.listen do |message|
		chat = Chat.find_by_chat_id(message.chat.id)
		if !chat
			chat = Chat.create(Chat.adapt(message.chat))
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
	Chat.find_each do |chat|
		begin
			$bot.api.send_chat_action(chat_id: chat.chat_id, action: action.to_s)
		rescue Telegram::Bot::Exceptions::ResponseError => e
			$bot.logger.info("The chat #{chat.ref} got an error.")
			$bot.logger.debug("Chat error: #{e}")
		end
	end
end 

def get_page_md5(page)
	html = RestClient.get(page.url)
	plain = HtmlToPlainText.plain_text(html)
	return Digest::MD5.hexdigest(plain), plain.size
end 

def notify_users(page)
	Chat.where(permit: true).each do |chat|
		$bot.logger.info("Notify chat #{chat.chat_id} (#{chat.ref})")
		send_message(chat, "La pagina [#{page.label}](#{page.url}) e' cambiata.")
	end
end

def talk
	t = BotTalk.where(sent: false).first
	return if !t
	$bot.logger.info("Found a message to send: #{t.sentence}")
	chats = Chat.where(permit: true)
	return if !chats
	chats.each do |chat|
		send_message(chat, t.sentence)
	end
	t.sent = true
	t.save
end

def pages_loop
	minute = 60
	while true
		next if !$bot
		Page.find_each do |page|
			send_chats_action(:typing)
			$bot.logger.info("Checking #{page['label']}")
			md5,bytes = get_page_md5(page)

			if !page.bytes
				page.bytes = bytes
				page.save
			end

			case
			when !page.md5
				$bot.logger.debug("No md5 for page #{page.label}, saving.")
				page.md5 = md5
				page.bytes = bytes
				page.save
			when md5 != page.md5
				$bot.logger.info("Page #{page.label} has changed. (#{md5} vs #{page.md5}")
				diff = bytes - page.bytes
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
			talk
			sleep 5
		rescue => e
			$bot.logger.error("Error in admin message loop: #{e}")
			log_lines(e.backtrace)
		end
	end
end
threads.each { |thr| thr.join }
