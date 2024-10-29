class Api::V2::GraphqlController < ApplicationController
  protect_from_forgery with: :null_session

  def execute
    variables = ensure_hash(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]

    result = OneclickCoreSchema.execute(
      query,
      variables: variables,
      context: { trip_planner: TripPlanner.new },
      operation_name: operation_name
    )

    render json: result
  rescue => e
    render json: { errors: [{ message: e.message }] }, status: 500
  end

  private

  def ensure_hash(ambiguous_param)
    case ambiguous_param
    when String then ambiguous_param.present? ? JSON.parse(ambiguous_param) : {}
    when Hash, ActionController::Parameters then ambiguous_param
    else {}
    end
  end
end
