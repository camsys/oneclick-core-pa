module Types
  class TripPlanType < Types::BaseObject
    field :itineraries, [Types::ItineraryType], null: true
  end
end