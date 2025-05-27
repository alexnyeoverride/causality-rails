class AddNextMainTurnCharacterIdStashedToGames < ActiveRecord::Migration[8.0]
  def change
    add_reference :games, :next_main_turn_character_id_stashed,
                  foreign_key: { to_table: :characters, on_delete: :nullify },
                  null: true,
                  index: true
  end
end
