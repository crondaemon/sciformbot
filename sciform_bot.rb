require 'telegram/bot'
require 'yaml'
require 'html_to_plain_text'
require 'rest-client'

CHATSFILE = 'chatsfile.yml'
CONTACTSFILE = 'contacts.yml'
PAGESFILE = 'pagesfile.yml'

def load_chats
	$chats = YAML.load_file(CHATSFILE)
end

def save_chats
	File.write(CHATSFILE, $chats.to_yaml)
end

$commands = Telegram::Bot::Types::ReplyKeyboardMarkup.new(resize_keyboard: true,
	keyboard: [
		['pagine' ,'watchers'],
		['aiuto', Telegram::Bot::Types::KeyboardButton.new(text: 'num. tel.', request_contact: true)],
])

def send_message(chat_id, text)
	begin
		$bot.api.send_message(chat_id: chat_id, reply_markup: $commands, parse_mode: 'Markdown', text: text)
	rescue Telegram::Bot::Exceptions::ResponseError
		$bot.logger.info("The chat #{chat_id} is no longer responding. Removing.")
		$chats.delete(chat_id)
		save_chats
	end
end 

def process_start(message)
	text = "Ciao #{message.from.first_name}, io sono il bot SciForm. "
	text << "Ti informero' su modifiche alle mie pagine monitorate. Solo gli utenti autorizzati "
	text << "possono accedere ai miei servizi. Devi mandarmi il tuo numero per ricevere le mie "
	text << "notifiche, cosi' posso verificare se sei autorizzato."
	send_message(message.chat.id, text)
end

def verify_contact(message)
	contacts = YAML.load_file(CONTACTSFILE).keys.map(&:to_s)
	if contacts.include?(message.contact.phone_number)
		$chats[message.chat.id] = { name: "#{message.from.first_name} #{message.from.last_name}" }
		save_chats
		send_message(message.chat.id, "Ok, sei autorizzato. Da questo momento riceverai le notifiche.")
	else
		send_message(message.chat.id, "Mi spiace, non sei un utente autorizzato.")
	end
end

def process_pages(message)
	return if !$pages
	text = "Le mie pagine monitorate sono:\n\n"

	$pages.each_with_index do |page,i|
		text << "#{i}) [#{page['label']}](#{page['url']})\n"
	end

	send_message(message.chat.id, text)
end

def process_help(message)
	text = "C'e' poco da sapere. Io controllo periodicamente alcune pagine e ti notifico se ci sono cambiamenti."
	text << "Ti mandero' anche il link alla pagina, per potervi cliccare."
	text << "Ci sono comandi aggiuntivi disponibili: scrivendo / ti verranno elencati."
	send_message(message.chat.id, text)
end

def process_watchers(message)
	send_message(message.chat.id, "Attualmente ci sono #{$chats.size} utenti in osservazione.")
end

def send_mail(from, text)
	`echo "[#{from}]: #{text}" | mail -s "Messaggio da SciFormBot" lomato@gmail.com`
end

def process_other(message)
	case $chats[message.chat.id]['status']
	when :bug
		header = "[BUG] "
		send_message(message.chat.id, "Bug segnalato, grazie.")
	when :feature
		header = "[FEATURE] "
		send_message(message.chat.id, "La richiesta e' stata inoltrata. Il mio padrone vedra' cosa puo' fare.")
	when nil
		header = ""
		send_message(message.chat.id, "Mi spiace, non ho capito.")
	end
	$chats[message.chat.id]['status'] = nil
	save_chats
	send_mail("#{message.from.first_name} #{message.from.last_name}", header + message.text)
end

def telegram_loop
	token = '469458692:AAGXSGyzD2Bo7KjOTEG-GtcmP6Ci8mZMCeo'
	$bot = Telegram::Bot::Client.new(token, logger: Logger.new(STDOUT))
	$bot.options[:timeout] = 3

	load_chats

	$bot.listen do |message|
		case
		when message.contact
			verify_contact(message)
		when message.text == '/start'
			process_start(message)
		when !message.text
			send_message(message.chat.id, "Non so gestire questo contenuto.")
		when message.text.start_with?('/bug')
			send_message(message.chat.id, "Stai segnalando un bug. Spiega il problema.")
			$chats[message.chat.id]['status'] = :bug
			save_chats
		when message.text.start_with?('/feature')
			send_message(message.chat.id, "Stai richiedendo una nuova feature. Descrivila brevemente.")
			$chats[message.chat.id]['status'] = :feature
			save_chats
		when message.text == 'watchers'
			process_watchers(message)
		when message.text == '/help' || message.text.downcase == 'aiuto'
			process_help(message)
		when message.text.downcase == 'pagine'
			process_pages(message)
		else
			process_other(message)
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
			$bot.logger.info("Sending content of #{file} to #{chat['user']}")
			send_message(chat_id, text)
		end
		FileUtils.rm(file)
	end
end

def pages_loop
	load_pages
	while true
		next if !$bot
		send_admin_message
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
		sleep 60
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
threads.each { |thr| thr.join }
