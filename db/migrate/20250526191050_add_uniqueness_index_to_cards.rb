class AddUniquenessIndexToCards < ActiveRecord::Migration[8.0]
  def change
    add_index :cards, [:owner_character_id, :location, :position], unique: true, name: 'index_cards_on_owner_loc_pos_uniqueness'
  end
end
