module Types
  class LegType < Types::BaseObject
    field :mode, String, null: false
    field :start_time, String, null: false
    field :end_time, String, null: false
    field :distance, Float, null: false
    field :from, Types::LocationType, null: true
    field :to, Types::LocationType, null: true
  end
end