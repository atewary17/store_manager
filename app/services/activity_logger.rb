class ActivityLogger
  # The single entry point for writing activity logs.
  # Always called AFTER the main transaction commits.
  # Never raises — a log failure must never affect the caller.

  def self.log(
    organisation:,
    activity_type:,
    description:,
    user: nil,
    activity_subtype: nil,
    quantity_litres: nil,
    reference: nil,
    metadata: {}
  )
    new(
      organisation:     organisation,
      activity_type:    activity_type,
      activity_subtype: activity_subtype,
      description:      description,
      user:             user,
      quantity_litres:  quantity_litres,
      reference:        reference,
      metadata:         metadata
    ).write
  end

  def initialize(**args)
    @organisation     = args[:organisation]
    @activity_type    = args[:activity_type]
    @activity_subtype = args[:activity_subtype]
    @description      = args[:description]
    @user             = args[:user]
    @quantity_litres  = args[:quantity_litres]
    @reference        = args[:reference]
    @metadata         = args[:metadata] || {}
  end

  def write
    ActivityLog.create!(
      organisation:     @organisation,
      user:             @user,
      activity_type:    @activity_type,
      activity_subtype: @activity_subtype,
      description:      @description,
      quantity_litres:  @quantity_litres,
      reference:        @reference,
      reference_type:   @reference&.class&.name,
      reference_id:     @reference&.id,
      metadata:         @metadata
    )
  rescue => e
    Rails.logger.error(
      "ActivityLogger failed: #{e.message} | " \
      "org=#{@organisation&.id} type=#{@activity_type} desc=#{@description}"
    )
    begin
      SystemEvent.log(
        severity:     :warning,
        source:       'activity_logger',
        title:        'Activity log write failed',
        message:      e.message,
        details:      { activity_type: @activity_type,
                        organisation_id: @organisation&.id }
      )
    rescue
      nil
    end
    nil
  end
end
