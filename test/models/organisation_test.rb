require "test_helper"

class OrganisationTest < ActiveSupport::TestCase
  setup do
    @org = organisations(:acme)
  end

  test "valid organisation" do
    assert @org.valid?
  end

  test "requires name" do
    @org.name = nil
    assert_not @org.valid?
  end

  test "gst_number uniqueness" do
    dup = Organisation.new(name: "Other Org", gst_number: @org.gst_number)
    assert_not dup.valid?
  end

  test "gst_number can be blank" do
    org = Organisation.new(name: "No GST Org", gst_number: "")
    assert org.valid?
  end

  test "subscription_plan enum" do
    assert @org.pro?
  end

  test "status enum" do
    assert @org.active?
  end

  test "has many users" do
    assert_respond_to @org, :users
  end

  test "available_products returns active products from assigned categories" do
    assert_respond_to @org, :available_products
  end
end
