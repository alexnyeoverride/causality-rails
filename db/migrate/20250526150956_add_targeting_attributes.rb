class AddTargetingAttributes < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      CREATE TYPE target_type_enum AS ENUM ('enemy', 'ally', 'self', 'card', 'next_draw');

      ALTER TABLE templates ADD COLUMN target_type_enum target_type_enum NOT NULL DEFAULT 'enemy';
      ALTER TABLE templates ADD COLUMN target_count_min integer NOT NULL DEFAULT 0;
      ALTER TABLE templates ADD COLUMN target_count_max integer NOT NULL DEFAULT 1;
      ALTER TABLE templates ADD COLUMN target_condition_key character varying NOT NULL DEFAULT '';

      ALTER TABLE cards ADD COLUMN target_type_enum target_type_enum;
      ALTER TABLE cards ADD COLUMN target_count_min integer;
      ALTER TABLE cards ADD COLUMN target_count_max integer;
      ALTER TABLE cards ADD COLUMN target_condition_key character varying;
    SQL
  end

  def down
    remove_column :templates, :target_type_enum
    remove_column :templates, :target_count_min
    remove_column :templates, :target_count_max
    remove_column :templates, :target_condition_key

    remove_column :cards, :target_type_enum
    remove_column :cards, :target_count_min
    remove_column :cards, :target_count_max
    remove_column :cards, :target_condition_key

    execute "DROP TYPE target_type_enum"
  end
end
