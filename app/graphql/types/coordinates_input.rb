module Types
  class CoordinatesInput < Types::BaseInputObject
    argument :lat, Float, required: true
    argument :lon, Float, required: true
  end
end