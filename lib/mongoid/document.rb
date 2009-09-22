module Mongoid #:nodoc:
  class Document #:nodoc:
    include ActiveSupport::Callbacks
    include Validatable

    AGGREGATE_REDUCE = "function(obj, prev) { prev.count++; }"
    GROUP_BY_REDUCE = "function(obj, prev) { prev.group.push(obj); }"

    attr_reader :attributes, :parent

    define_callbacks \
      :after_create,
      :after_save,
      :after_validation,
      :before_create,
      :before_save,
      :before_validation

    class << self

      # Get an aggregate count for the supplied group of fields and the
      # selector that is provided.
      def aggregate(fields, selector)
        collection.group(fields, selector, { :count => 0 }, AGGREGATE_REDUCE)
      end

      # Create an association to a parent Document.
      def belongs_to(association_name)
        add_association(:belongs_to, association_name.to_s.classify, association_name)
      end

      # Get the Mongo::Collection associated with this Document.
      def collection
        @collection_name = self.to_s.demodulize.tableize
        @collection ||= Mongoid.database.collection(@collection_name)
      end

      # Create a new Document with the supplied attribtues, and insert it into the database.
      def create(attributes = {})
        new(attributes).save
      end

      # Defines all the fields that are accessable on the Document
      # For each field that is defined, a getter and setter will be
      # added as an instance method to the Document.
      def fields(*names)
        @fields = []
        names.flatten.each do |name|
          @fields << name
          define_method(name) { read_attribute(name) }
          define_method("#{name}=") { |value| write_attribute(name, value) }
        end
      end

      # Find all Documents in several ways.
      # Model.find(:first, :attribute => "value")
      # Model.find(:all, :attribute => "value")
      def find(*args)
        case args[0]
        when :all then find_all(args[1])
        when :first then find_first(args[1])
        else find_first(Mongo::ObjectID.from_string(args[0].to_s))
        end
      end

      # Find a single Document given the passed selector, which is a Hash of attributes that
      # must match the Document in the database exactly.
      def find_first(selector = nil)
        new(collection.find_one(selector))
      end

      # Find all Documents given the passed selector, which is a Hash of attributes that
      # must match the Document in the database exactly.
      def find_all(selector = nil)
        collection.find(selector).collect { |doc| new(doc) }
      end

      # Find all Documents given the supplied criteria, grouped by the fields
      # provided.
      def group_by(fields, selector)
        collection.group(fields, selector, { :group => [] }, GROUP_BY_REDUCE).collect do |docs|
          group!(docs)
        end
      end

      # Create a one-to-many association between Documents.
      def has_many(association_name)
        add_association(:has_many, association_name.to_s.classify, association_name)
      end

      # Create a one-to-many association between Documents.
      def has_one(association_name)
        add_association(:has_one, association_name.to_s.titleize, association_name)
      end

      # Find all documents in paginated fashion given the supplied arguments.
      # If no parameters are passed just default to offset 0 and limit 20.
      def paginate(selector = nil, params = {})
        collection.find(selector, Mongoid::Paginator.new(params).options).collect { |doc| new(doc) }
      end

    end

    # Get the Mongo::Collection associated with this Document.
    def collection
      self.class.collection
    end

    # Delete this Document from the database.
    def destroy
      collection.remove(:_id => id)
    end

    # Get the Mongo::ObjectID associated with this object.
    # This is in essence the primary key.
    def id
      @attributes[:_id]
    end

    # Instantiate a new Document, setting the Document's attirbutes if given.
    # If no attributes are provided, they will be initialized with an empty Hash.
    def initialize(attributes = {})
      @attributes = attributes.symbolize_keys if attributes
      @attributes = {} unless attributes
    end

    # Returns true is the Document has not been persisted to the database, false if it has.
    def new_record?
      @attributes[:_id].nil?
    end

    # Set the parent to this document.
    def parent=(document)
      @parent = document
    end

    # Save this document to the database. If this document is the root document
    # in the object graph, it will save itself, and return self. If the
    # document is embedded within another document, or is multiple levels down
    # the tree, the root object will get saved, and return itself.
    def save
      run_callbacks(:before_save)
      if @parent
        run_callbacks(:after_save)
        @parent.save
      else
        collection.save(@attributes)
        run_callbacks(:after_save)
        return self
      end
    end

    # Returns the id of the Document
    def to_param
      id.to_s
    end

    # Update the attributes of this Document and return true
    def update_attributes(attributes)
      @attributes = attributes.symbolize_keys!; save; true
    end

    private

    class << self

      # Adds the association to the associations hash with the type as the key, 
      # then adds the accessors for the association.
      def add_association(type, class_name, name)
        define_method(name) do
          Mongoid::Associations::AssociationFactory.create(type, name, self)
        end
        define_method("#{name}=") do |object|
          @attributes[name] = object.mongoidize
        end
      end

      # Takes the supplied raw grouping of documents and alters it to a
      # grouping of actual document objects.
      def group!(docs)
        docs["group"] = docs["group"].collect { |attrs| new(attrs) }; docs
      end

    end

    # Read from the attributes hash.
    def read_attribute(name)
      @attributes[name.to_sym]
    end

    # Write to the attributes hash.
    def write_attribute(name, value)
      @attributes[name.to_sym] = value
    end

  end
end
