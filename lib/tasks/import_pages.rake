namespace :db do
	namespace :import do
		desc 'Import pages'
		task pages: :environment do
			pages = YAML.load_file('pagesfile.yml')
			pages.each do |page|
				p = Page.create(page)
				if !p
					puts "Error in page #{page}"
				end
			end
		end

		desc 'Import chats'
		task chats: :environment do
			chats = YAML.load_file('chatsfile.yml')
			chats.each_pair do |chat_id,chat|
				c = Chat.create(Chat.adapt(chat))
				if !c
					puts "Error in chat #{chat}"
				end
			end
		end
	end
end
