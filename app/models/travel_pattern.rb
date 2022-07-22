class TravelPattern < ApplicationRecord
  scope :ordered, -> {joins(:agency).order("agencies.name, travel_patterns.name")}
  scope :for_superuser, -> {all}
  scope :for_oversight_user, -> (user) {where(agency: user.current_agency.agency_oversight_agency.pluck(:transportation_agency_id))}
  scope :for_transport_user, -> (user) {where(agency: user.current_agency)}

  belongs_to :agency
  belongs_to :booking_window

  has_many :travel_pattern_services, dependent: :destroy
  has_many :services, through: :travel_pattern_services
  has_many :travel_pattern_service_schedules, dependent: :destroy
  has_many :service_schedules, through: :travel_pattern_service_schedules
  has_many :travel_pattern_purposes, dependent: :destroy
  has_many :purposes, through: :travel_pattern_purposes
  has_many :travel_pattern_funding_sources, dependent: :destroy
  has_many :funding_sources, through: :travel_pattern_funding_sources

  accepts_nested_attributes_for :travel_pattern_service_schedules, allow_destroy: true, reject_if: proc { |attr| attr[:service_schedule_id].blank? }
  accepts_nested_attributes_for :travel_pattern_purposes, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :travel_pattern_funding_sources, allow_destroy: true, reject_if: :all_blank

  validates :name, uniqueness: {scope: :agency_id}
  validates_presence_of :name, :booking_window, :agency

  def self.for_user(user)
    if user.superuser?
      for_superuser.ordered
    elsif user.currently_oversight?
      for_oversight_user(user).ordered
    elsif user.currently_transportation?
      for_transport_user(user).order("name desc")
    else
      nil
    end
  end

  def schedules_by_type
    # Prepping the return value
    schedules_by_type = {
      weekly_schedules: [],
      extra_service_schedules: [],
      reduced_service_schedules: [],
    }

    # Get all associated schedules (in reverse alphabetical order)
    service_schedules = self.travel_pattern_service_schedules
                            .eager_load(service_schedule: :service_schedule_type)
                            .joins(:service_schedule)
                            .merge(ServiceSchedule.order(name: :desc))
                            .to_a
    
    # Sort Schedules by type
    # This also reverses the order, so now they're sorted alphabetically
    while service_schedules.length > 0 do
      schedule = service_schedules.pop

      schedules_by_type[:weekly_schedules].push(schedule) if schedule.is_a_weekly_schedule?
      schedules_by_type[:extra_service_schedules].push(schedule) if schedule.is_an_extra_service_schedule?
      schedules_by_type[:reduced_service_schedules].push(schedule) if schedule.is_a_reduced_service_schedule?
    end

    return schedules_by_type
  end
end