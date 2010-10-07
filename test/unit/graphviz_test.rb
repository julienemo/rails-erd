require File.expand_path("../test_helper", File.dirname(__FILE__))

class GraphvizTest < ActiveSupport::TestCase
  def setup
    RailsERD.options.filetype = :png
    RailsERD.options.warn = false
    load "rails_erd/diagram/graphviz.rb"
  end
  
  def teardown
    FileUtils.rm Dir["ERD.*"] rescue nil
    RailsERD::Diagram.send :remove_const, :Graphviz rescue nil
  end
  
  def diagram(options = {})
    @diagram ||= Diagram::Graphviz.new(Domain.generate(options), options).tap do |diagram|
      diagram.generate
    end
  end
  
  def find_dot_nodes(diagram)
    [].tap do |nodes|
      diagram.graph.each_node do |name, node|
        nodes << node
      end
    end
  end

  def find_dot_node(diagram, name)
    diagram.graph.get_node(name)
  end

  def find_dot_node_pairs(diagram)
    [].tap do |edges|
      diagram.graph.each_edge do |edge|
        edges << [edge.node_one, edge.node_two]
      end
    end
  end
  
  def find_dot_edges(diagram)
    [].tap do |edges|
      diagram.graph.each_edge do |edge|
        edges << edge
      end
    end
  end
  
  def find_dot_edge_styles(diagram)
    find_dot_edges(diagram).map { |e| [e[:arrowtail].to_s.tr('"', ''), e[:arrowhead].to_s.tr('"', '')] }
  end

  # Diagram properties =======================================================
  test "file name should depend on file type" do
    create_simple_domain
    begin
      assert_equal "ERD.svg", Diagram::Graphviz.create(:filetype => :svg)
    ensure
      FileUtils.rm "ERD.svg" rescue nil
    end
  end
  
  test "rank direction should be lr for horizontal orientation" do
    create_simple_domain
    assert_equal '"LR"', diagram(:orientation => :horizontal).graph[:rankdir].to_s
  end

  test "rank direction should be tb for vertical orientation" do
    create_simple_domain
    assert_equal '"TB"', diagram(:orientation => :vertical).graph[:rankdir].to_s
  end
  
  # Diagram generation =======================================================
  test "create should create output for domain with attributes" do
    create_model "Foo", :bar => :references, :column => :string do
      belongs_to :bar
    end
    create_model "Bar", :column => :string
    Diagram::Graphviz.create
    assert File.exists?("ERD.png")
  end

  test "create should create output for domain without attributes" do
    create_simple_domain
    Diagram::Graphviz.create
    assert File.exists?("ERD.png")
  end
  
  test "create should write to file with dot extension if type is dot" do
    create_simple_domain
    Diagram::Graphviz.create :filetype => :dot
    assert File.exists?("ERD.dot")
  end

  test "create should write to file with dot extension without requiring graphviz" do
    create_simple_domain
    begin
      GraphViz.class_eval do
        alias_method :old_output_and_errors_from_command, :output_and_errors_from_command
        def output_and_errors_from_command(*args); raise end
      end
      assert_nothing_raised do
        Diagram::Graphviz.create :filetype => :dot
      end
    ensure
      GraphViz.class_eval do
        alias_method :output_and_errors_from_command, :old_output_and_errors_from_command
      end
    end
  end
  
  test "create should create output for domain with attributes if orientation is vertical" do
    create_model "Foo", :bar => :references, :column => :string do
      belongs_to :bar
    end
    create_model "Bar", :column => :string
    Diagram::Graphviz.create(:orientation => :vertical)
    assert File.exists?("ERD.png")
  end

  test "create should create output for domain if orientation is vertical" do
    create_simple_domain
    Diagram::Graphviz.create(:orientation => :vertical)
    assert File.exists?("ERD.png")
  end

  test "create should not create output if there are no connected models" do
    Diagram::Graphviz.create rescue nil
    assert !File.exists?("ERD.png")
  end

  test "create should abort and complain if there are no connected models" do
    message = nil
    begin
      Diagram::Graphviz.create
    rescue => e
      message = e.message
    end
    assert_match /No entities found/, message
  end
  
  test "create should write to given file name plus extension if present" do
    begin
      create_simple_domain
      Diagram::Graphviz.create :filename => "foobar"
      assert File.exists?("foobar.png")
    ensure
      FileUtils.rm "foobar.png" rescue nil
    end
  end
  
  test "create should abort and complain if output directory does not exist" do
    message = nil
    begin
      create_simple_domain
      Diagram::Graphviz.create :filename => "does_not_exist/foo"
    rescue => e
      message = e.message
    end
    assert_match /Output directory 'does_not_exist' does not exist/, message
  end

  # Graphviz output ==========================================================
  test "generate should create directed graph" do
    create_simple_domain
    assert_equal "digraph", diagram.graph.type
  end
  
  test "generate should add title to graph" do
    create_simple_domain
    assert_equal '"Domain model\n\n"', diagram.graph.graph[:label].to_s
  end

  test "generate should add title with application name to graph" do
    begin
      Object::Quux = Module.new
      Object::Quux::Application = Class.new
      Object::Rails = Struct.new(:application).new(Object::Quux::Application.new)
      create_simple_domain
      assert_equal '"Quux domain model\n\n"', diagram.graph.graph[:label].to_s
    ensure
      Object::Quux.send :remove_const, :Application
      Object.send :remove_const, :Quux
      Object.send :remove_const, :Rails
    end
  end

  test "generate should omit title if set to false" do
    create_simple_domain
    assert_equal "", diagram(:title => false).graph.graph[:label].to_s
  end
  
  test "generate should create node for each entity" do
    create_model "Foo", :bar => :references do
      belongs_to :bar
    end
    create_model "Bar"
    assert_equal ["Bar", "Foo"], find_dot_nodes(diagram).map(&:id).sort
  end
  
  test "generate should add label for entities" do
    create_model "Foo", :bar => :references do
      belongs_to :bar
    end
    create_model "Bar"
    assert_match %r{<\w+.*?>Bar</\w+>}, find_dot_node(diagram, "Bar")[:label].to_gv
  end

  test "generate should add attributes to entity labels" do
    create_model "Foo", :bar => :references do
      belongs_to :bar
    end
    create_model "Bar", :column => :string
    assert_match %r{<\w+.*?>column <\w+.*?>string</\w+.*?>}, find_dot_node(diagram, "Bar")[:label].to_gv
  end

  test "generate should not add any attributes to entity labels if attributes is set to false" do
    create_model "Jar", :contents => :string
    create_model "Lid", :jar => :references do
      belongs_to :jar
    end
    assert_no_match %r{contents}, find_dot_node(diagram(:attributes => false), "Jar")[:label].to_gv
  end

  test "generate should create edge for each relationship" do
    create_model "Foo", :bar => :references do
      belongs_to :bar
    end
    create_model "Bar", :foo => :references do
      belongs_to :foo
    end
    assert_equal [["Bar", "Foo"], ["Foo", "Bar"]], find_dot_node_pairs(diagram).sort
  end
  
  test "node records should have direction reversing braces for vertical orientation" do
    create_model "Book", :author => :references do
      belongs_to :author
    end
    create_model "Author", :name => :string
    assert_match %r(\A<\{\s*<.*\|.*>\s*\}>\Z)m, find_dot_node(diagram(:orientation => :vertical), "Author")[:label].to_gv
  end

  test "node records should not have direction reversing braces for horizontal orientation" do
    create_model "Book", :author => :references do
      belongs_to :author
    end
    create_model "Author", :name => :string
    assert_match %r(\A<\s*<.*\|.*>\s*>\Z)m, find_dot_node(diagram(:orientation => :horizontal), "Author")[:label].to_gv
  end
  
  # Simple notation style ====================================================
  test "generate should use no style for one to one cardinalities with simple notation" do
    create_one_to_one_assoc_domain
    assert_equal [["none", "none"]], find_dot_edge_styles(diagram(:notation => :simple))
  end

  test "generate should use normal arrow head for one to many cardinalities with simple notation" do
    create_one_to_many_assoc_domain
    assert_equal [["none", "normal"]], find_dot_edge_styles(diagram(:notation => :simple))
  end

  test "generate should use normal arrow head and tail for many to many cardinalities with simple notation" do
    create_many_to_many_assoc_domain
    assert_equal [["normal", "normal"]], find_dot_edge_styles(diagram(:notation => :simple))
  end

  # Advanced notation style ===================================================
  test "generate should use open dots for one to one cardinalities with advanced notation" do
    create_one_to_one_assoc_domain
    assert_equal [["odot", "odot"]], find_dot_edge_styles(diagram(:notation => :advanced))
  end

  test "generate should use dots for mandatory one to one cardinalities with advanced notation" do
    create_one_to_one_assoc_domain
    One.class_eval do
      validates_presence_of :other
    end
    assert_equal [["odot", "dot"]], find_dot_edge_styles(diagram(:notation => :advanced))
  end

  test "generate should use normal arrow and open dot head with dot tail for one to many cardinalities with advanced notation" do
    create_one_to_many_assoc_domain
    assert_equal [["odot", "odotnormal"]], find_dot_edge_styles(diagram(:notation => :advanced))
  end

  test "generate should use normal arrow and dot head for mandatory one to many cardinalities with advanced notation" do
    create_one_to_many_assoc_domain
    One.class_eval do
      validates_presence_of :many
    end
    assert_equal [["odot", "dotnormal"]], find_dot_edge_styles(diagram(:notation => :advanced))
  end

  test "generate should use normal arrow and open dot head and tail for many to many cardinalities with advanced notation" do
    create_many_to_many_assoc_domain
    assert_equal [["odotnormal", "odotnormal"]], find_dot_edge_styles(diagram(:notation => :advanced))
  end

  test "generate should use normal arrow and dot tail and head for mandatory many to many cardinalities with advanced notation" do
    create_many_to_many_assoc_domain
    Many.class_eval do
      validates_presence_of :more
    end
    More.class_eval do
      validates_presence_of :many
    end
    assert_equal [["dotnormal", "dotnormal"]], find_dot_edge_styles(diagram(:notation => :advanced))
  end
end
