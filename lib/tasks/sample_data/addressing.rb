module Addressing
  private

  def address(string)
    state = country.states.first
    parts = string.split(", ")
    Spree::Address.new(
      address1: parts[0],
      city: parts[1],
      zipcode: parts[2],
      state: state,
      country: country
    )
  end

  def zone
    zone = Spree::Zone.find_or_create_by_name!("Australia")
    zone.members.create(zonable: country)
    zone
  end

  def country
    Spree::Country.find_by_iso(ENV.fetch('DEFAULT_COUNTRY_CODE'))
  end
end
