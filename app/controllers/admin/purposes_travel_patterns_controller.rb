class Admin::PurposesTravelPatternsController < Admin::AdminController

  def index
    @agencies = Agency.accessible_by(current_ability)
    @purposes = Purpose.accessible_by(current_ability)
                       .joins(:agency)
                       .merge(Agency.order(:name))
                       .includes(:agency)
    authorize! :read, @purposes
  end

  def show
    @purpose = Purpose.find(params[:id])
    authorize! :read, @purpose
  end

  def destroy
    @purpose = Purpose.find(params[:id])
    authorize! :destroy, @purpose
    @purpose.destroy

    redirect_to admin_trip_purposes_path
  end

  def new
    query = params.fetch(:query)
    agency = Agency.find(query[:agency_id])
    @purpose = Purpose.new(agency: agency)
    authorize! :create, @purpose
  end

  def create
    @purpose = Purpose.new(purpose_params)
    @purpose.agency_id = params[:agency_id]
    authorize! :create, @purpose
  	@purpose.save

  	redirect_to admin_trip_purposes_path
  end

  def edit
    @purpose = Purpose.includes(:agency).find(params[:id])
    authorize! :edit, @purpose
  end

  def update
    @purpose = Purpose.find(params[:id])
    authorize! :edit, @purpose
    @purpose.update(purpose_params)
    redirect_to admin_trip_purposes_path
  end

  private

  def purpose_params
  	params.require(:purpose).permit(:name, :description)
  end

end