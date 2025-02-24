# Helper class for uploading a KML file and reading it.
class KMLUploader
  require 'geospatial/kml/reader'
  require 'nokogiri'

  attr_reader :errors, :custom_geo, :warnings

  # Initialize with a path to a KML file
  def initialize(file, opts={})
    @file = file
    @path = opts[:path] || @file.tempfile.path
    # NOTE: the name field is specific to Travel Patterns
    @name = opts[:name]
    @agency = opts[:agency].present? ? Agency.find(opts[:agency]) : nil
    @filetype = opts[:content_type] || @file.content_type
    @model = opts[:geo_type].to_s.classify.constantize
    @column_mappings = opts[:column_mappings] || {name: 'NAME', state: 'STATEFP'}
    @errors = []
    @custom_geo = nil
    @warnings = []
    Rails.logger.info "KMLUploader initialized with file type: #{@filetype}, name: #{@name}, agency: #{@agency.try(:id)}, model: #{@model}"
  end

  # Call load to process the uploaded filepath into geometric database records
  def load
    @errors.clear
    Rails.logger.info "Opening file at path: #{@path}..."
    if @filetype == "application/vnd.google-earth.kml+xml" || @filetype == "application/octet-stream"
      Rails.logger.info "File type valid (#{@filetype}). Proceeding with load_kmlfile."
      load_kmlfile(@path)
    else
      Rails.logger.error "Invalid file type detected: #{@filetype}"
      @errors << "Please upload a .kml file."
    end
    Rails.logger.info "Load completed. Errors: #{@errors.inspect}, Warnings: #{@warnings.inspect}"
    return self
  end

  def successful?
    @errors.empty?
  end

  private

  def load_kmlfile(file_name)
    Rails.logger.info "Reading Shapes into #{@model.to_s} Table from file: #{file_name}..."
    begin
      reader = Geospatial::KML::Reader.load_file(@path)
      polygon_count = reader.polygons.count rescue 0
      linestring_count = (reader.respond_to?(:linestrings) ? reader.linestrings.count : 0)
      Rails.logger.info "Total polygons found in KML: #{polygon_count}, total linestrings found: #{linestring_count}"
      
      # Fallback: if no features found via the gem, use Nokogiri parsing.
      if polygon_count == 0 && linestring_count == 0
        Rails.logger.info "No features found via Geospatial::KML::Reader; falling back to Nokogiri parsing..."
        file_content = File.read(@path)
        doc = Nokogiri::XML(file_content)
        ns = {"kml" => "http://www.opengis.net/kml/2.2"}
        lines = doc.xpath("//kml:LineString", ns)
        Rails.logger.info "Nokogiri found #{lines.count} LineString element(s)."
        if lines.count > 0
          coords_node = lines.first.xpath(".//kml:coordinates", ns).first
          if coords_node
            coords_text = coords_node.text.strip
            Rails.logger.info "Coordinates text (first 100 chars): #{coords_text[0..100]}..."
            coords_arr = coords_text.split(/\s+/).map { |s| s.split(',').map(&:to_f) }
            Rails.logger.info "Parsed #{coords_arr.size} coordinate point(s)."
            # Ensure the linestring is closed
            if coords_arr.first != coords_arr.last
              Rails.logger.info "LineString is not closed. Closing it automatically."
              coords_arr << coords_arr.first
            end
            points_wkt = coords_arr.map { |pt| "#{pt[0]} #{pt[1]}" }.join(", ")
            polygon_wkt = "POLYGON((#{points_wkt}))"
            Rails.logger.info "Constructed WKT from Nokogiri parsing (first 100 chars): #{polygon_wkt[0..100]}..."
            factory = RGeo::ActiveRecord::SpatialFactoryStore.instance.default
            polygon_geom = factory.parse_wkt(polygon_wkt)
            output_geom = factory.multi_polygon([]).union(polygon_geom)
            geom = RGeo::Feature.cast(output_geom, RGeo::Feature::MultiPolygon)
            Rails.logger.info "Parsed geometry: #{geom.as_text}" if geom.respond_to?(:as_text)
            record = ActiveRecord::Base.logger.silence do
              Rails.logger.info "Creating record for CustomGeography with name: #{@name}, agency: #{@agency.try(:id)}"
              @custom_geo = @model.create({ name: @name, agency: @agency })
              Rails.logger.info "Record after create: #{@custom_geo.inspect}"
              @custom_geo.update_attributes(geom: geom)
              Rails.logger.info "Record after updating geom: #{@custom_geo.inspect}"
              if @custom_geo.errors.present?
                Rails.logger.error "Encountered errors: #{@custom_geo.errors.full_messages.to_sentence}"
                @errors << "#{@custom_geo.errors.full_messages.to_sentence} for #{@custom_geo.name}."
              else
                @custom_geo
              end
            end
            if record
              Rails.logger.info "SUCCESS! Record created successfully via Nokogiri fallback."
            else
              Rails.logger.error "FAILED to create record via Nokogiri fallback."
            end
            return
          else
            Rails.logger.error "No coordinates found in Nokogiri parsed LineString."
            @errors << "No coordinates found in the KML file."
            return
          end
        else
          Rails.logger.error "No valid polygon or linestring features found in the KML file."
          @errors << "No valid polygon or linestring features found in the KML file."
          return
        end
      end

      # If features are found via the gem, use them.
      geometry_source = nil
      feature_type = nil

      if polygon_count > 0
        geometry_source = reader.polygons.first
        feature_type = 'polygon'
      elsif linestring_count > 0
        geometry_source = reader.linestrings.first
        feature_type = 'linestring'
      end

      Rails.logger.info "Processing a new #{feature_type}: #{geometry_source.inspect}"
      fail_count = 0
      Rails.logger.info "Current model: #{@model.name}, expected: #{CustomGeography.name}"
      Rails.logger.info "Dashboard mode is: #{Config.dashboard_mode}"
      if @model.name == CustomGeography.name && Config.dashboard_mode == 'travel_patterns'
        Rails.logger.info "Inside travel_patterns block for record creation."
        if (feature_type == 'polygon' && polygon_count > 1) || (feature_type == 'linestring' && linestring_count > 1)
          Rails.logger.warn "Multiple features detected; uploader only accepts one feature."
          @warnings << 'Found multiple features while creating a custom geography. Uploader only accepts one feature'
        else
          Rails.logger.info "Single feature detected; proceeding to load record for #{@name}."
          points = geometry_source.points
          if feature_type == 'linestring'
            first_point = points.first
            last_point = points.last
            unless first_point == last_point
              Rails.logger.info "LineString is not closed. Closing it automatically."
              points << first_point
            end
          end
          polygon_points = []
          points.each do |point|
            point_str = [point[0], point[1]].join(" ")
            Rails.logger.info "Processing point: #{point_str}"
            polygon_points.push(point_str.to_s)
          end
          polygon_wkt = 'POLYGON((' + polygon_points.join(", ") + '))'
          Rails.logger.info "Constructed WKT: #{polygon_wkt}"
          factory = RGeo::ActiveRecord::SpatialFactoryStore.instance.default
          polygon_geom = factory.parse_wkt(polygon_wkt)
          output_geom = factory.multi_polygon([]).union(polygon_geom)
          geom = RGeo::Feature.cast(output_geom, RGeo::Feature::MultiPolygon)
          Rails.logger.info "Parsed geometry: #{geom.as_text}" if geom.respond_to?(:as_text)
          record = ActiveRecord::Base.logger.silence do
            Rails.logger.info "Creating record for CustomGeography with name: #{@name}, agency: #{@agency.try(:id)}"
            @custom_geo = @model.create({ name: @name, agency: @agency })
            Rails.logger.info "Record after create: #{@custom_geo.inspect}"
            @custom_geo.update_attributes(geom: geom)
            Rails.logger.info "Record after updating geom: #{@custom_geo.inspect}"
            if @custom_geo.errors.present?
              Rails.logger.error "Encountered errors: #{@custom_geo.errors.full_messages.to_sentence}"
              @errors << "#{@custom_geo.errors.full_messages.to_sentence} for #{@custom_geo.name}."
            else
              @custom_geo
            end
          end
        end
        if record
          Rails.logger.info "SUCCESS! Record created successfully."
        else
          Rails.logger.error "FAILED to create record."
          fail_count += 1
        end
        @errors << "#{fail_count} record(s) failed to load." if fail_count > 0
      else
        Rails.logger.info "Skipping record creation because model/dashboard mode conditions are not met."
      end

    rescue StandardError => ex
      Rails.logger.error "Exception encountered in load_kmlfile: #{ex.message}"
      puts ex.message
      @errors << "An error occurred while unpacking the uploaded KML file. Please double check your KML file and try again"
    end
  end

end
