module Types
  class ItineraryType < Types::BaseObject
    field :start_time, String, null: false
    field :end_time, String, null: false
    field :duration, Integer, null: false
    field :legs, [Types::LegType], null: true
  end
end
