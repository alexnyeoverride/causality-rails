module CardBulkOperations
  extend ActiveSupport::Concern

  def bulk_update_cards(card_ids_to_update:, new_positions_map: {}, target_location_name: nil)
    return [] if card_ids_to_update.blank?
    safe_card_ids = card_ids_to_update.map(&:to_i).uniq
    return [] if safe_card_ids.empty?

    relevant_positions_map = if new_positions_map.present?
                               new_positions_map.select { |id, _pos| safe_card_ids.include?(id.to_i) }
                                                .transform_keys(&:to_i)
                                                .transform_values(&:to_i)
                             else
                               {}
                             end
    has_position_updates = relevant_positions_map.any?
    has_location_update = target_location_name.present?

    return [] unless has_position_updates || has_location_update

    set_parts = []
    bind_values = []

    if has_position_updates
      position_case_sql = "position = CASE id "
      relevant_positions_map.each do |card_id, new_pos|
        position_case_sql << "WHEN #{card_id.to_i} THEN #{new_pos.to_i} "
      end
      position_case_sql << "ELSE position END"
      set_parts << position_case_sql
    end

    if has_location_update
      set_parts << "location = ?"
      bind_values << target_location_name.to_s
    end

    set_parts << "updated_at = ?"
    bind_values << Time.current

    sql_set_clause = set_parts.join(', ')
    affected_rows = 0

    Card.transaction do
      ActiveRecord::Base.connection.execute('SET CONSTRAINTS index_cards_on_owner_loc_pos_uniqueness DEFERRED')
      affected_rows = Card.where(id: safe_card_ids).update_all([sql_set_clause, *bind_values])
    end

    affected_rows > 0 ? safe_card_ids.sort : []
  end
end
