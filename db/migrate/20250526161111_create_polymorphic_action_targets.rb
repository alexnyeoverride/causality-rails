class CreatePolymorphicActionTargets < ActiveRecord::Migration[8.0]
  def up
    rename_table :action_targets, :action_character_targets

    create_table :action_card_targets do |t|
      t.references :action, null: false, foreign_key: { on_delete: :cascade }
      t.references :target_card, null: false, foreign_key: { to_table: :cards, on_delete: :cascade }
      t.timestamps default: -> { 'NOW()' }

      t.index [:action_id, :target_card_id], unique: true, name: 'index_action_card_targets_on_action_and_card'
    end
  end

  def down
    drop_table :action_card_targets

    rename_table :action_character_targets, :action_targets

    rename_index :action_targets, "index_action_character_targets_on_action_id", "index_action_targets_on_action_id"
  end
end
