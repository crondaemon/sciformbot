class Chat < ApplicationRecord
	def self.adapt(h)
		h[:chat_id] = h[:id]
		h.delete(:id)
		h[:chat_type] = h[:type]
		h.delete(:type)
		h
	end

	def ref
		title || "#{first_name} #{last_name}"
	end
end
