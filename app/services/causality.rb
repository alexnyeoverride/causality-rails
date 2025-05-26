class Causality
  attr_reader :game

  def initialize(game)
    @game = game
  end

  def add(action_to_save:)
    action_to_save.save

    if action_to_save.persisted?
      check_and_advance_trigger_phase(action_to_save.trigger_id) if action_to_save.trigger_id.present?
    end
    action_to_save
  end

  def get_next_tickable
    sql_for_action_ids = <<-SQL
      SELECT
        primary_actions_table.id
      FROM
        actions AS primary_actions_table
        INNER JOIN cards AS cards_for_filtering ON primary_actions_table.card_id = cards_for_filtering.id
        INNER JOIN templates AS templates_for_filtering ON cards_for_filtering.template_id = templates_for_filtering.id
        LEFT JOIN actions AS trigger_actions_for_filtering ON primary_actions_table.trigger_id = trigger_actions_for_filtering.id
                                                         AND primary_actions_table.game_id = trigger_actions_for_filtering.game_id
      WHERE
        primary_actions_table.game_id = :game_id AND
        primary_actions_table.phase NOT IN ('resolved', 'failed') AND
        (
          primary_actions_table.phase = 'reacted_to' OR
          (primary_actions_table.phase = 'declared' AND templates_for_filtering.name = 'Pass')
        ) AND
        (
          primary_actions_table.trigger_id IS NULL OR
          trigger_actions_for_filtering.id IS NOT NULL AND
          (
            (primary_actions_table.resolution_timing = 'before' AND trigger_actions_for_filtering.phase IN ('declared', 'reacted_to', 'started', 'resolved', 'failed')) OR
            (primary_actions_table.resolution_timing = 'after' AND trigger_actions_for_filtering.phase = 'resolved') OR
            (primary_actions_table.resolution_timing IS NULL AND trigger_actions_for_filtering.phase = 'resolved')
          )
        )
      ORDER BY primary_actions_table.id ASC;
    SQL

    parameterized_sql = ActiveRecord::Base.send(:sanitize_sql_array, [sql_for_action_ids, { game_id: @game.id }])
    action_ids = ActiveRecord::Base.connection.execute(parameterized_sql).map { |row| row['id'] }

    return nil if action_ids.empty?

    all_structurally_plausible_actions = Action
      .where(id: action_ids)
      .includes(
        :trigger,
        { card: :template },
        :source
      )
      .order(:id)

    return nil if all_structurally_plausible_actions.empty?

    find_actual_first_to_resolve = lambda do |current_action_candidate, all_actions_context_for_recursion|
      potential_preempting_reactions = all_actions_context_for_recursion.select do |potential_reaction|
        potential_reaction.trigger_id == current_action_candidate.id &&
        potential_reaction.resolution_timing.to_s == 'before' &&
        potential_reaction.phase != 'resolved' && potential_reaction.phase != 'failed'
      end.sort_by(&:id)

      potential_preempting_reactions.each do |reaction|
        if reaction.can_tick?
          return find_actual_first_to_resolve.call(reaction, all_actions_context_for_recursion)
        end
      end
      current_action_candidate
    end

    all_structurally_plausible_actions.each do |potential_initial_action|
      if potential_initial_action.can_tick?
        return find_actual_first_to_resolve.call(potential_initial_action, all_structurally_plausible_actions)
      end
    end
    nil
  end

  def get_next_trigger
    game.actions
        .joins(card: :template)
        .where(actions: { phase: 'declared' })
        .where.not(templates: { name: 'Pass' })
        .order('actions.id ASC')
        .first
  end

  def fail_recursively!(root_action_id)
    sql = <<-SQL
      WITH RECURSIVE failure_chain AS (
        SELECT id, card_id, source_id, game_id
        FROM actions
        WHERE id = $1 AND game_id = $2
        UNION ALL
        SELECT r.id, r.card_id, r.source_id, r.game_id
        FROM actions r
        INNER JOIN failure_chain fc ON r.trigger_id = fc.id AND r.game_id = fc.game_id
        WHERE r.phase NOT IN ('resolved', 'failed') AND r.id != fc.id
      )
      UPDATE actions
      SET phase = 'failed', updated_at = $3
      WHERE id IN (SELECT id FROM failure_chain) AND game_id = $2
      RETURNING id, card_id, source_id;
    SQL

    bindings = [
      ActiveRecord::Relation::QueryAttribute.new("root_action_id_param", root_action_id, ActiveRecord::Type::Integer.new),
      ActiveRecord::Relation::QueryAttribute.new("game_id_param", game.id, ActiveRecord::Type::Integer.new),
      ActiveRecord::Relation::QueryAttribute.new("current_time_param", Time.current, ActiveRecord::Type::DateTime.new)
    ]

    result = ActiveRecord::Base.connection.exec_query(
      sql,
      "Fail Actions Recursively and Return Card/Source Info",
      bindings
    )
    result.to_a
  end

  private

  def check_and_advance_trigger_phase(trigger_action_id)
    trigger_action = game.actions.find_by(id: trigger_action_id)
    return unless trigger_action && trigger_action.phase.to_s == 'declared'

    potential_reactors = game.characters.alive.to_a

    responses_to_trigger = game.actions.where(trigger_id: trigger_action_id)
    responding_character_ids = responses_to_trigger.pluck(:source_id).uniq

    all_potential_reactors_responded = potential_reactors.all? do |character|
      responding_character_ids.include?(character.id)
    end

    if potential_reactors.empty? || all_potential_reactors_responded
      trigger_action.update_column(:phase, :reacted_to)
    end
  end
end
