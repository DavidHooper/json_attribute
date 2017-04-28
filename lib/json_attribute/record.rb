require 'json_attribute/attribute_definition'
require 'json_attribute/record/container_attribute_type'

module JsonAttribute
  # The mix-in to provide JsonAttribute support to ActiveRecord::Base models.
  # We call it `Record` instead of `ActiveRecord` to avoid confusing namespace
  # shadowing errors, sorry!
  #
  #    class SomeModel < ActiveRecord::Base
  #      include JsonAttribute::Record
  #
  #      json_attribute :a_number, :integer
  #    end
  #
  module Record
    extend ActiveSupport::Concern

    included do
      unless self < ActiveRecord::Base
        raise TypeError, "JsonAttribute::Record can only be used with an ActiveRecord::Base model. #{self} does not appear to be one. Are you looking for ::JsonAttribute::Model?"
      end

      class_attribute :json_attributes_registry, instance_accessor: false
      self.json_attributes_registry = {}

      scope(:json_attributes_where, lambda do |attributes|
        attributes = attributes.collect do |key, value|
          attr_def = json_attributes_registry[key.to_sym]

          [attr_def.store_key, attr_def.serialize(attr_def.cast value)]
        end.to_h

        where("#{table_name}.json_attributes @> (?)::jsonb", attributes.to_json)
      end)
    end


    class_methods do
      # Type can be a symbol that will be looked up in `ActiveModel::Type.lookup`,
      # or anything that's an ActiveSupport::Type-like thing (usually
      # subclassing ActiveSupport::Type::Value)
      #
      # TODO, doc or
      def json_attribute(name, type,
                         container_attribute: AttributeDefinition::DEFAULT_CONTAINER_ATTRIBUTE,
                         **options)
        self.json_attributes_registry = json_attributes_registry.merge(
          name.to_sym => AttributeDefinition.new(name.to_sym, type, options.merge(container_attribute: container_attribute))
        )

        _json_attributes_module.module_eval do
          define_method("#{name}=") do |value|
            attribute_def = self.class.json_attributes_registry.fetch(name.to_sym)

            # write_store_attribute copied from Rails store_accessor implementation.
            # https://github.com/rails/rails/blob/74c3e43fba458b9b863d27f0c45fd2d8dc603cbc/activerecord/lib/active_record/store.rb#L90-L96
            write_store_attribute(attribute_def.container_attribute, attribute_def.store_key, attribute_def.cast(value))
          end

          define_method("#{name}") do
            attribute_def = self.class.json_attributes_registry.fetch(name.to_sym)

            # read_store_attribute copied from Rails store_accessor implementation.
            # https://github.com/rails/rails/blob/74c3e43fba458b9b863d27f0c45fd2d8dc603cbc/activerecord/lib/active_record/store.rb#L90-L96
            from_hash_value = read_store_attribute(attribute_def.container_attribute, attribute_def.store_key)
return from_hash_value
            # If this already is of the correct cast type, cast will generally
            # quickly return itself, so this is actually a cheap way to lazily
            # convert and memoize serialized verison to proper in-memory object.
            # They'll be properly serialized out by Rails.... we think. Might
            # need a custom serializer on the json attribute, we'll see.
            # casted = attribute_def.deserialize(from_hash_value)
            # unless casted.equal?(from_hash_value)
            #   write_store_attribute(attribute_def.container_attribute, name.to_s, casted)
            # end

            # return casted
          end
        end
      end

      private

      # Define an anonymous module and include it, so can still be easily
      # overridden by concrete class. Design cribbed from ActiveRecord::Store
      # https://github.com/rails/rails/blob/4590d7729e241cb7f66e018a2a9759cb3baa36e5/activerecord/lib/active_record/store.rb
      def _json_attributes_module # :nodoc:
        @_json_attributes_module ||= begin
          mod = Module.new
          include mod
          mod
        end
      end
    end
  end
end