class MakeCardPositionConstraintDeferrable < ActiveRecord::Migration[8.0]
  def up
    # Remove the uniqueness index that exists, because bulk updates are checked for uniqueness row-by-row by default.
    # This triggers an error when shuffling the positions of cards in the deck.
    # It is possible to use a uniqueness index which only runs at the end of a transaction instead.
    remove_index :cards, name: 'index_cards_on_owner_loc_pos_uniqueness'

    execute <<-SQL
      ALTER TABLE cards
      ADD CONSTRAINT index_cards_on_owner_loc_pos_uniqueness
      UNIQUE (owner_character_id, location, position)
      DEFERRABLE INITIALLY IMMEDIATE;
    SQL
  end

  def down
    remove_index :cards, name: 'index_cards_on_owner_loc_pos_uniqueness'
    add_index :cards, [:owner_character_id, :location, :position], unique: true, name: 'index_cards_on_owner_loc_pos_uniqueness'
  end
end
