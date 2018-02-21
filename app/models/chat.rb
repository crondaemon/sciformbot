class Chat < ApplicationRecord
	validates :chat_id, uniqueness: true

	def self.adapt(chat)
		h = chat.to_h
		h[:chat_id] = h[:id]
		h[:chat_type] = h[:type]
		h.slice(:chat_id, :chat_type, :title, :username, :first_name, :last_name)
	end

	def ref
		title || "#{first_name} #{last_name}"
	end
end
