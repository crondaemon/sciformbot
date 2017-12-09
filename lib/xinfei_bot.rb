require 'telegram/bot'

$commands = Telegram::Bot::Types::ReplyKeyboardMarkup.new(one_time_keyboard: true, resize_keyboard: true,
	keyboard: [
			['cos\'è la XinFei?', 'dove sono i corsi'], 
			%w(orari costi promo),
			%w(sito contatti)
		])

def sanitize(text)
	text.gsub!('\'', '')
	text.gsub!('è', 'e')
	text.gsub!('é', 'e')
	text.gsub!('à', 'a')
	text.gsub!('ì', 'i')
	text.gsub!('ò', 'o')
	text.gsub!('ù', 'u')
	return text.downcase
end

def key(message)
	ret = :unknown

	clean_msg = sanitize(message)

	ret = :general if clean_msg == 'corsi'

	ret = :where if clean_msg.include?('dove')

	ret = :about if clean_msg == 'chi'
	ret = :about if clean_msg.include?('cose') && clean_msg.include?('xinfei')
	ret = :about if clean_msg.include?('chi') && clean_msg.include?('siete')

	ret = :costs if clean_msg.include?('cost')

	ret = :site if clean_msg.include?('sito')
	ret = :site if clean_msg.include?('web')

	ret = :contacts if clean_msg == 'contatti'
	ret = :contacts if clean_msg.include?('facebook')
	ret = :contacts if clean_msg.include?('telefono')
	ret = :contacts if clean_msg.include?('mail')
	ret = :contacts if clean_msg.include?('contattar')

	ret = :hours if clean_msg.include?('orar')
	ret = :hours if clean_msg.include?('quando')

	ret = :thanks if clean_msg.include?('grazie')
	
	ret = :promo if clean_msg.include?('promo')

	return ret
end

def send_additional(key, bot, chat_id)
	case key
	when :where
		bot.api.send_location(chat_id: chat_id, latitude: 45.068717, longitude: 7.670221, disable_notification: true, reply_markup: $commands)
	end
end

def answer(bot, message, key)
	filename = key.to_s + ".msg"
	begin
		content = File.read(filename)
		bot.api.send_message(chat_id: message.chat.id, text: content, parse_mode: 'Markdown', reply_markup: $commands)
		send_additional(key, bot, message.chat.id)
	rescue => e
		bot.logger.debug(e.inspect)
		bot.api.send_message(chat_id: message.chat.id, text: "Temo di avere qualche problema...", reply_markup: $commands)
	end
end

# MAIN

token = '246996184:AAEm-HCWLJLpHlNd-tAUuVz5vamwo9Yv3Dw'

while true
	begin
		bot = Telegram::Bot::Client.new(token, logger: Logger.new('xinfei-bot.log'))
		bot.options[:timeout] = 3

		bot.listen do |message|
			next if !message.text

			if message.text == '/start'
				bot.logger.info("#{message.from.first_name} #{message.from.last_name} (#{message.from.username}) entered chat")
				bot.api.send_message(chat_id: message.chat.id, reply_markup: $commands,
					text: "Ciao #{message.from.first_name}, io sono il bot della XinFei, dimmi cosa vuoi sapere.")
				next
			end

			bot.logger.info("[#{message.from.first_name} #{message.from.last_name}]: #{message.text}")

			key, additional = key(message.text)
			bot.logger.debug("key: #{key}")
			if key == :unknown
				bot.api.send_message(chat_id: message.chat.id, text: "Non capisco. Dimmi cosa vuoi sapere.")
			else
				answer(bot, message, key)
			end
		end
	rescue => e
	end
end