require 'spec_helper'
require 'test_components'
require 'rspec-steps'

describe "polymorphic relationships", js: true, skip: true do

  before(:all) do
    require 'pusher'
    require 'pusher-fake'
    Pusher.app_id = "MY_TEST_ID"
    Pusher.key =    "MY_TEST_KEY"
    Pusher.secret = "MY_TEST_SECRET"
    require "pusher-fake/support/base"

    Hyperstack.configuration do |config|
      config.transport = :pusher
      config.channel_prefix = "synchromesh"
      config.opts = {app_id: Pusher.app_id, key: Pusher.key, secret: Pusher.secret}.merge(PusherFake.configuration.web_options)
    end

    class ActiveRecord::Base
      class << self
        def public_columns_hash
          @public_columns_hash ||= {}
        end
      end
    end
  end

  before(:each) do

    # spec_helper resets the policy system after each test so we have to setup
    # before each test
    stub_const 'TestApplicationPolicy', Class.new
    TestApplicationPolicy.class_eval do
      always_allow_connection
      regulate_all_broadcasts { |policy| policy.send_all }
      allow_change(to: :all, on: [:create, :update, :destroy]) { true }
    end

    size_window(:small, :large)

    isomorphic do

      class Picture < ActiveRecord::Base
        def self.build_tables
          connection.create_table :pictures, force: true do |t|
            t.string :name
            t.integer :imageable_id
            t.string :imageable_type
            t.timestamps
          end
          ActiveRecord::Base.public_columns_hash[name] = columns_hash
        end

        belongs_to :imageable, polymorphic: true
      end

      class Employee < ActiveRecord::Base
        def self.build_tables
          connection.create_table :employees, force: true do |t|
            t.string :name
            t.string :ss
            t.timestamps
          end
          ActiveRecord::Base.public_columns_hash[name] = columns_hash
        end
        has_many :pictures, as: :imageable
      end

      class Product < ActiveRecord::Base
        def self.build_tables
          connection.create_table :products, force: true do |t|
            t.string :name
            t.string :description
            t.timestamps
          end
          ActiveRecord::Base.public_columns_hash[name] = columns_hash
        end
        has_many :pictures, as: :imageable
      end

      class Avatar < ActiveRecord::Base
        def self.build_tables
          connection.create_table :products, force: true do |t|
            t.string :name
            t.string :description
            t.timestamps
          end
          ActiveRecord::Base.public_columns_hash[name] = columns_hash
        end
        has_one :picture, as: :imageable
      end


      class Membership < ActiveRecord::Base
        def self.build_tables
          connection.create_table :memberships, force: true do |t|
            t.integer :uzer_id
            t.integer :memerable_id
            t.string  :memerable_type
            t.timestamps
          end
          ActiveRecord::Base.public_columns_hash[name] = columns_hash
        end

        belongs_to :uzer
        belongs_to :memerable, polymorphic: true
      end

      class Project < ActiveRecord::Base
        def self.build_tables
          connection.create_table :projects, force: true do |t|
            t.string :name
            t.string :project_data
            t.timestamps
          end
          ActiveRecord::Base.public_columns_hash[name] = columns_hash
        end

        has_many :memberships, as: :memerable, dependent: :destroy
        has_many :uzers, through: :memberships
      end

      class Group < ActiveRecord::Base
        def self.build_tables
          connection.create_table :groups, force: true do |t|
            t.string :name
            t.string :group_data
            t.timestamps
          end
          ActiveRecord::Base.public_columns_hash[name] = columns_hash
        end

        has_many :memberships, as: :memerable, dependent: :destroy
        has_many :uzers, through: :memberships
      end

      class Uzer < ActiveRecord::Base
        def self.build_tables
          connection.create_table :uzers, force: true do |t|
            t.string :name
            t.string :uzer_data
            t.timestamps
          end
          ActiveRecord::Base.public_columns_hash[name] = columns_hash
        end

        has_many :memberships
        has_many :groups,   through: :memberships, source: :memerable, source_type: 'Group'
        has_many :projects, through: :memberships, source: :memerable, source_type: 'Project'
      end


    end

    [Picture, Employee, Product, Membership, Project, Group, Uzer].each { |klass| klass.build_tables }

  end

  context "simple polymorphic relationship" do
    before(:each) do
      @imageable1 = Employee.create(name: 'imageable1', ss: '123')
      @picture11 =  Picture.create(name:  'picture11',  imageable:   @imageable1)
      @picture12 =  Picture.create(name:  'picture12',  imageable:   @imageable1)
      @imageable2 = Product.create(name:  'imageable2', description: 'product1 description')
      @picture21 =  Picture.create(name:  'picture21',  imageable:   @imageable2)
      @picture22 =  Picture.create(name:  'picture22',  imageable:   @imageable2)
      @imageable3 = Product.create(name:  'imageable3', description: 'product2 description')

    end

    def compare_to_server(model, expression, expected_result, load=true)
      server_side = eval("#{model.class}.find(#{model.id}).#{expression}")
      expect(server_side).to eq(expected_result)
      if load
        expect_promise("Hyperstack::Model.load { #{model.class}.find(#{model.id}).#{expression} }")
        .to contain_exactly(*expected_result)
      else
        wait_for_ajax
        expect_evaluate_ruby("#{model.class}.find(#{model.id}).#{expression}").to contain_exactly(*expected_result)
      end
    end

    it 'read belongs_to' do
      compare_to_server @picture11, 'imageable.name',        'imageable1'
      compare_to_server @picture11, 'imageable.ss',          '123'
      compare_to_server @picture21, 'imageable.name',        'imageable2'
      compare_to_server @picture21, 'imageable.description', 'product1 description'
      compare_to_server @picture12, 'imageable.name',        'imageable1'
      compare_to_server @picture12, 'imageable.ss',          '123'
      compare_to_server @picture22, 'imageable.name',        'imageable2'
      compare_to_server @picture22, 'imageable.description', 'product1 description'
    end

    it 'read has_many' do
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11', 'picture12']
      compare_to_server @imageable2, 'pictures.collect(&:name)', ['picture21', 'picture22']
    end

    it 'create has_many client side' do
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11', 'picture12']
      evaluate_promise "pic = Picture.new(name: 'picture13'); #{@imageable1.class}.find(#{@imageable1.id}).pictures << pic; pic.save"
      @imageable1.reload
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11', 'picture12', 'picture13'], false
    end

    it 'create belongs_to client side' do
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11', 'picture12']
      evaluate_ruby "Picture.create(name: 'picture14', imageable: #{@imageable1.class}.find(#{@imageable1.id}))"
      wait_for_ajax
      @imageable1.reload
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11', 'picture12', 'picture14'], false
    end

    it 'create server side with broadcast update' do
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11', 'picture12']
      Picture.create(name: 'picture15', imageable: @imageable1)
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11', 'picture12', 'picture15'], false
    end

    it 'destroy client side' do
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11', 'picture12']
      evaluate_promise "Picture.find(#{@picture12.id}).destroy"
      @imageable1.reload
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11'], false
    end

    it 'destroy server side with broadcast update' do
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11', 'picture12']
      @picture12.destroy
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11']
    end

    it 'changing belongs to relationship on client' do
      # not working yet
      # compare_to_server @picture11, 'imageable.name',        'imageable1'
      # compare_to_server @picture21, 'imageable.name',        'imageable2'
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11', 'picture12']
      compare_to_server @imageable2, 'pictures.collect(&:name)', ['picture21', 'picture22']

      evaluate_ruby do
        p = Picture.find(1)
        p.imageable = Product.find(1)
        p.save
      end
      binding.pry
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture12'], false
      compare_to_server @imageable2, 'pictures.collect(&:name)', ['picture11', 'picture21', 'picture22'], false
    end

    it 'changing belongs to relationship on server' do
      # just debugging here... when id doesn't change we don't realize that data is changing
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture11', 'picture12']
      compare_to_server @imageable2, 'pictures.collect(&:name)', ['picture21', 'picture22']

      wait_for_ajax
      p = Picture.find_by_name('picture11')
      p.imageable = @imageable2
      p.save
      wait_for_ajax
      compare_to_server @imageable1, 'pictures.collect(&:name)', ['picture12']
      compare_to_server @imageable2, 'pictures.collect(&:name)', ['picture11', 'picture21', 'picture22']
    end


  end

  context "many-to-many polymorphic relationship" do
    before(:each) do
      @uzer1 = Uzer.create(name: 'uzer1', uzer_data: 'uzer data1')
      @uzer2 = Uzer.create(name: 'uzer2', uzer_data: 'uzer data2')
      @uzer3 = Uzer.create(name: 'uzer3', uzer_data: 'uzer data3')
      @group1 = Group.create(name: 'group1', group_data: 'group data1')
      @group1 = Group.create(name: 'group2', group_data: 'group data2')
      @group1 = Group.create(name: 'group3', group_data: 'group data3')
      @project1 = Project.create(name: 'project1', project_data: 'project data1')
      @project2 = Project.create(name: 'project2', project_data: 'project data2')
      @project3 = Project.create(name: 'project3', project_data: 'project data3')
    end

    it 'loads previously defined data client side' do
      @uzer1.groups << @group1
      # run this on client after above
      expect(@group1.uzers.collect(&:id)).to eq [@uzer1.id]
    end

    it 'creates due to a broadcast client side' do
      expect(@group1.uzers.count).to eq(0)  # client side
      @uzer1.groups << @group1 # server side
      expect(@group1.uzers.collect(&:id)).to eq [@uzer1.id] # client side
    end

    it 'destroys due to a broadcast client side' do
      @uzer1.groups << @group1 # server side
      expect(@group1.uzers.collect(&:id)).to eq [@uzer1.id] # client
      Membership.find_by(uzer: @uzer1, memerable: @group1).destroy # server side
      expect(@group1.uzers.count).to eq(0)  # client side
    end

    it 'updates the server when new entries are made on the client' do
      @uzer1.groups << @group1 # client side
      @uzer1.save # needed for client side semantics
      expect(@group1.uzers.collect(&:id)).to eq [@uzer1.id] # server side
    end

    it 'updates the server when entries are deleted on the client' do
      @uzer1.groups << @group1 # server side
      Membership.find_by(uzer: @uzer1, memerable: @group1).destroy # client side
      expect(@group1.uzers.count).to eq(0)  # server side
    end

  end

end