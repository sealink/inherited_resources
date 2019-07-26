module InheritedResources
  # = URLHelpers
  #
  # When you use InheritedResources it creates some UrlHelpers for you.
  # And they handle everything for you.
  #
  #  # /posts/1/comments
  #  resource_url          # => /posts/1/comments/#{@comment.to_param}
  #  resource_url(comment) # => /posts/1/comments/#{comment.to_param}
  #  new_resource_url      # => /posts/1/comments/new
  #  edit_resource_url     # => /posts/1/comments/#{@comment.to_param}/edit
  #  collection_url        # => /posts/1/comments
  #  parent_url            # => /posts/1
  #
  #  # /projects/1/tasks
  #  resource_url          # => /projects/1/tasks/#{@task.to_param}
  #  resource_url(task)    # => /projects/1/tasks/#{task.to_param}
  #  new_resource_url      # => /projects/1/tasks/new
  #  edit_resource_url     # => /projects/1/tasks/#{@task.to_param}/edit
  #  collection_url        # => /projects/1/tasks
  #  parent_url            # => /projects/1
  #
  #  # /users
  #  resource_url          # => /users/#{@user.to_param}
  #  resource_url(user)    # => /users/#{user.to_param}
  #  new_resource_url      # => /users/new
  #  edit_resource_url     # => /users/#{@user.to_param}/edit
  #  collection_url        # => /users
  #  parent_url            # => /
  #
  # The nice thing is that those urls are not guessed during runtime. They are
  # all created when you inherit.
  #
  module UrlHelpers

    def resource_url_helper_name
      self.resources_configuration[:self][:resource_url_helper_name] || :resource
    end


    def resources_url_helper_name
      self.resources_configuration[:self][:resources_url_helper_name] || resource_url_helper_name.to_s.pluralize.to_sym
    end


    def collection_url_helper_name
      self.resources_configuration[:self][:collection_url_helper_name] || :collection
    end


    def parent_url_helper_name
      self.resources_configuration[:self][:parent_url_helper_name] || :parent
    end


    protected

    # This method hard code url helpers in the class.
    #
    # We are doing this because is cheaper than guessing them when our action
    # is being processed (and even more cheaper when we are using nested
    # resources).
    #
    # When we are using polymorphic associations, those helpers rely on
    # polymorphic_url Rails helper.
    #
    def create_resources_url_helpers!
      resource_segments, resource_ivars = [], []
      resource_config = self.resources_configuration[:self]

      singleton   = resource_config[:singleton]
      uncountable = !singleton && resource_config[:route_collection_name] == resource_config[:route_instance_name]
      polymorphic = self.parents_symbols.include?(:polymorphic)

      # Add route_prefix if any.
      unless resource_config[:route_prefix].blank?
        if polymorphic
          resource_ivars << resource_config[:route_prefix].to_s.inspect
        else
          resource_segments << resource_config[:route_prefix]
        end
      end

      # Deal with belongs_to associations and polymorphic associations.
      # Remember that we don't have to build the segments in polymorphic cases,
      # because the url will be polymorphic_url.
      #
      self.parents_symbols.each do |symbol|
        if symbol == :polymorphic
          resource_ivars << :parent
        else
          config = self.resources_configuration[symbol]
          if config[:singleton] && polymorphic
            resource_ivars << config[:instance_name].inspect
          else
            resource_segments << config[:route_name]
          end
          if !config[:singleton]
            resource_ivars    << :"@#{config[:instance_name]}"
          end
        end
      end

      collection_ivars    = resource_ivars.dup
      collection_segments = resource_segments.dup


      # Generate parent url before we add resource instances.
      unless parents_symbols.empty?
        generate_url_and_path_helpers nil,   parent_url_helper_name, resource_segments, resource_ivars
        generate_url_and_path_helpers :edit, parent_url_helper_name, resource_segments, resource_ivars
      end

      # This is the default route configuration, later we have to deal with
      # exception from polymorphic and singleton cases.
      #
      collection_segments << resource_config[:route_collection_name]
      resource_segments   << resource_config[:route_instance_name]
      resource_ivars      << :"@#{resource_config[:instance_name]}"

      # In singleton cases, we do not send the current element instance variable
      # because the id is not in the URL. For example, we should call:
      #
      #   project_manager_url(@project)
      #
      # Instead of:
      #
      #   project_manager_url(@project, @manager)
      #
      # Another exception in singleton cases is that collection url does not
      # exist. In such cases, we create the parent collection url. So in the
      # manager case above, the collection url will be:
      #
      #    project_url(@project)
      #
      # If the singleton does not have a parent, it will default to root_url.
      #
      # Finally, polymorphic cases we have to give hints to the polymorphic url
      # builder. This works by attaching new ivars as symbols or records.
      #
      if singleton
        collection_segments.pop
        resource_ivars.pop

        if polymorphic
          resource_ivars << resource_config[:instance_name].inspect
          new_ivars       = resource_ivars
        end
      elsif polymorphic
        collection_ivars << '(@_resource_class_new ||= resource_class.new)'
      end

      # If route is uncountable then add "_index" suffix to collection index route name
      if uncountable
        collection_segments << :"#{collection_segments.pop}_index"
      end

      generate_url_and_path_helpers nil,   collection_url_helper_name, collection_segments, collection_ivars
      generate_url_and_path_helpers :new,  resource_url_helper_name,   resource_segments,   new_ivars || collection_ivars
      generate_url_and_path_helpers nil,   resource_url_helper_name,   resource_segments,   resource_ivars
      generate_url_and_path_helpers :edit, resource_url_helper_name,   resource_segments,   resource_ivars

      if resource_config[:custom_actions]
        [*resource_config[:custom_actions][:resource]].each do | method |
          generate_url_and_path_helpers method, resource_url_helper_name, resource_segments, resource_ivars
        end
        [*resource_config[:custom_actions][:collection]].each do | method |
          generate_url_and_path_helpers method, resources_url_helper_name, collection_segments, collection_ivars
        end
      end
    end

    def handle_shallow_resource(prefix, name, segments, ivars) #:nodoc:
      return segments, ivars unless self.resources_configuration[:self][:shallow]
      case name
      when collection_url_helper_name, resources_url_helper_name
        segments = segments[-2..-1]
        ivars = [ivars.last]
      when resource_url_helper_name
        if prefix == :new
          segments = segments[-2..-1]
          ivars = [ivars.last]
        else
          segments = [segments.last]
          ivars = [ivars.last]
        end
      when parent_url_helper_name
        segments = [segments.last]
        ivars = [ivars.last]
      end

      segments ||= []

      unless self.resources_configuration[:self][:route_prefix].blank?
        segments.unshift self.resources_configuration[:self][:route_prefix]
      end

      return segments, ivars
    end

    def generate_url_and_path_helpers(prefix, name, resource_segments, resource_ivars) #:nodoc:
      resource_segments, resource_ivars = handle_shallow_resource(prefix, name, resource_segments, resource_ivars)

      ivars       = resource_ivars.dup
      singleton   = self.resources_configuration[:self][:singleton]
      polymorphic = self.parents_symbols.include?(:polymorphic)

      # If it's not a singleton, ivars are not empty, not a collection or
      # not a "new" named route, we can pass a resource as argument.
      #
      unless (singleton && name != parent_url_helper_name) || ivars.empty? || name == collection_url_helper_name || prefix == :new
        ivars.push "(given_args.first || #{ivars.pop})"
      end

      # In collection in polymorphic cases, allow an argument to be given as a
      # replacemente for the parent.
      #
      if name == collection_url_helper_name && polymorphic
        index = ivars.index(:parent)
        ivars.insert index, "(given_args.first || parent)"
        ivars.delete(:parent)
      end

      # When polymorphic is true, the segments must be replace by :polymorphic
      # and ivars should be gathered into an array, which is compacted when
      # optional.
      #
      if polymorphic
        segments = :polymorphic
        ivars    = "[#{ivars.join(', ')}]"
        ivars   << '.compact' if self.resources_configuration[:polymorphic][:optional]
      else
        segments = resource_segments.empty? ? 'root' : resource_segments.join('_')
        ivars    = ivars.join(', ')
      end

      prefix = prefix ? "#{prefix}_" : ''
      ivars << (ivars.empty? ? 'given_options' : ', given_options')

      given_args_transform = 'given_args = given_args.collect { |arg| arg.respond_to?(:permitted?) ? arg.to_h : arg }'

      class_eval <<-URL_HELPERS, __FILE__, __LINE__
        protected
          undef :#{prefix}#{name}_path if method_defined? :#{prefix}#{name}_path
          def #{prefix}#{name}_path(*given_args)
            #{given_args_transform}
            given_options = given_args.extract_options!
            #{prefix}#{segments}_path(#{ivars})
          end

          undef :#{prefix}#{name}_url if method_defined? :#{prefix}#{name}_url
          def #{prefix}#{name}_url(*given_args)
            #{given_args_transform}
            given_options = given_args.extract_options!
            #{prefix}#{segments}_url(#{ivars})
          end

          helper_method :#{prefix}#{name}_path
          helper_method :#{prefix}#{name}_url
      URL_HELPERS
    end

  end
end
