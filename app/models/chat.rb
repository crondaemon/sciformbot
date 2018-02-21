class Chat < ApplicationRecord
	validates :chat_id, uniqueness: true

	def self.adapt(chat)
		h = chat.to_h
		h[:chat_id] = h[:id]
		h.delete(:id)
		h[:chat_type] = h[:type]
		h.delete(:type)
		h.delete(:photo)
		h.delete(:description)
		h.delete(:invite_link)
		h.delete(:pinned_message)
		h.delete(:all_members_are_administrators)
		h
	end

	def ref
		title || "#{first_name} #{last_name}"
	end
end
