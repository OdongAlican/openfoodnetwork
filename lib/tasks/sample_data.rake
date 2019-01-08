require "tasks/sample_data/addressing"
require "tasks/sample_data/logging"

# The sample data generated by this task is supposed to save some time during
# manual testing. It is not meant to be complete, but we try to improve it
# over time. How much is hardcoded here is a trade off between developer time
# and tester time. We also can't include secrets like payment gateway
# configurations in the code since it's public. We have been discussing this for
# a while:
#
# - https://community.openfoodnetwork.org/t/seed-data-development-provisioning-deployment/910
# - https://github.com/openfoodfoundation/openfoodnetwork/issues/2072
#
namespace :openfoodnetwork do
  desc 'load sample data for development or staging'
  task sample_data: :environment do
    raise "Please run `rake db:seed` first." unless seeded?

    users = UserFactory.new.create_samples

    enterprises = EnterpriseFactory.new.create_samples(users)

    PermissionFactory.new.create_samples(enterprises)

    FeeFactory.new.create_samples(enterprises)

    ShippingMethodFactory.new.create_samples(enterprises)

    PaymentMethodFactory.new.create_samples(enterprises)

    TaxonFactory.new.create_samples

    products = ProductFactory.new.create_samples(enterprises)

    InventoryFactory.new.create_samples(products)

    OrderCycleFactory.new.create_samples

    CustomerFactory.new.create_samples(users)

    GroupFactory.new.create_samples
  end

  def seeded?
    Spree::User.count > 0 &&
      Spree::Country.count > 0 &&
      Spree::State.count > 0
  end

  class UserFactory
    include Logging

    def create_samples
      log "Creating users:"
      usernames.map { |name|
        create_user(name)
      }.to_h
    end

    private

    def usernames
      [
        "Manel Super Admin",
        "Penny Profile",
        "Fred Farmer",
        "Freddy Shop Farmer",
        "Fredo Hub Farmer",
        "Mary Retailer",
        "Maryse Private",
        "Jane Customer"
      ]
    end

    def create_user(name)
      email = "#{name.downcase.tr(' ', '.')}@example.org"
      password = Spree::User.friendly_token
      log "- #{email}"
      user = Spree::User.create_with(
        password: password,
        password_confirmation: password,
        confirmation_sent_at: Time.zone.now,
        confirmed_at: Time.zone.now
      ).find_or_create_by_email!(email)
      [name, user]
    end
  end

  class EnterpriseFactory
    include Logging
    include Addressing

    def create_samples(users)
      log "Creating enterprises:"
      enterprise_data(users).map do |data|
        name = data[:name]
        log "- #{name}"
        Enterprise.create_with(data).find_or_create_by_name!(name)
      end
    end

    private

    # rubocop:disable Metrics/MethodLength
    def enterprise_data(users)
      [
        {
          name: "Penny's Profile",
          owner: users["Penny Profile"],
          is_primary_producer: false,
          sells: "none",
          address: address("25 Myrtle Street, Bayswater, 3153")
        },
        {
          name: "Fred's Farm",
          owner: users["Fred Farmer"],
          is_primary_producer: true,
          sells: "none",
          address: address("6 Rollings Road, Upper Ferntree Gully, 3156")
        },
        {
          name: "Freddy's Farm Shop",
          owner: users["Freddy Shop Farmer"],
          is_primary_producer: true,
          sells: "own",
          address: address("72 Lake Road, Blackburn, 3130")
        },
        {
          name: "Fredo's Farm Hub",
          owner: users["Fredo Hub Farmer"],
          is_primary_producer: true,
          sells: "any",
          address: address("7 Verbena Street, Mordialloc, 3195")
        },
        {
          name: "Mary's Online Shop",
          owner: users["Mary Retailer"],
          is_primary_producer: false,
          sells: "any",
          address: address("20 Galvin Street, Altona, 3018")
        },
        {
          name: "Maryse's Private Shop",
          owner: users["Maryse Private"],
          is_primary_producer: false,
          sells: "any",
          address: address("6 Martin Street, Belgrave, 3160"),
          require_login: true
        }
      ]
    end
    # rubocop:enable Metrics/MethodLength
  end

  class PaymentMethodFactory
    include Logging
    include Addressing

    def create_samples(enterprises)
      log "Creating payment methods:"
      distributors = enterprises.select(&:is_distributor)
      distributors.each do |enterprise|
        create_payment_methods(enterprise)
      end
    end

    private

    def create_payment_methods(enterprise)
      return if enterprise.payment_methods.present?
      log "- #{enterprise.name}"
      create_cash_method(enterprise)
      create_card_method(enterprise)
    end

    def create_cash_method(enterprise)
      create_payment_method(
        enterprise,
        "Cash on collection",
        "Pay on collection!",
        Spree::Calculator::FlatRate.new
      )
    end

    def create_card_method(enterprise)
      create_payment_method(
        enterprise,
        "Credit card (fake)",
        "We charge 1%, but won't ask for you details. ;-)",
        Spree::Calculator::FlatPercentItemTotal.new(preferred_flat_percent: 1)
      )
    end

    def create_payment_method(enterprise, name, description, calculator)
      card = enterprise.payment_methods.new(
        name: name,
        description: description,
        distributor_ids: [enterprise.id]
      )
      card.calculator = calculator
      card.save!
    end
  end

  class ShippingMethodFactory
    include Logging
    include Addressing

    def create_samples(enterprises)
      log "Creating shipping methods:"
      distributors = enterprises.select(&:is_distributor)
      distributors.each do |enterprise|
        create_shipping_methods(enterprise)
      end
    end

    private

    def create_shipping_methods(enterprise)
      return if enterprise.shipping_methods.present?
      log "- #{enterprise.name}"
      create_pickup(enterprise)
      create_delivery(enterprise)
    end

    def create_pickup(enterprise)
      create_shipping_method(
        enterprise,
        name: "Pickup",
        description: "pick-up at your awesome hub gathering place",
        require_ship_address: false,
        calculator_type: "Calculator::Weight"
      )
    end

    def create_delivery(enterprise)
      delivery = create_shipping_method(
        enterprise,
        name: "Home delivery",
        description: "yummy food delivered at your door",
        require_ship_address: true,
        calculator_type: "Spree::Calculator::FlatRate"
      )
      delivery.calculator.preferred_amount = 2
      delivery.calculator.save!
    end

    def create_shipping_method(enterprise, params)
      params[:distributor_ids] = [enterprise.id]
      method = enterprise.shipping_methods.new(params)
      method.zone = zone
      method.save!
      method
    end
  end

  class FeeFactory
    include Logging

    def create_samples(enterprises)
      log "Creating fees:"
      enterprises.each do |enterprise|
        next if enterprise.enterprise_fees.present?
        log "- #{enterprise.name} charges markup"
        calculator = Calculator::FlatPercentPerItem.new(preferred_flat_percent: 10)
        create_fee(enterprise, calculator)
        calculator.save!
      end
    end

    private

    def create_fee(enterprise, calculator)
      fee = enterprise.enterprise_fees.new(
        fee_type: "sales",
        name: "markup",
        inherits_tax_category: true,
      )
      fee.calculator = calculator
      fee.save!
    end
  end

  class PermissionFactory
    include Logging

    def create_samples(enterprises)
      all_permissions = [
        :add_to_order_cycle,
        :manage_products,
        :edit_profile,
        :create_variant_overrides
      ]
      enterprises.each do |enterprise|
        log "#{enterprise.name} permits everybody to do everything."
        enterprise_permits_to(enterprise, enterprises, all_permissions)
      end
    end

    private

    def enterprise_permits_to(enterprise, receivers, permissions)
      receivers.each do |receiver|
        EnterpriseRelationship.where(
          parent_id: enterprise,
          child_id: receiver
        ).first_or_create!(
          parent: enterprise,
          child: receiver,
          permissions_list: permissions
        )
      end
    end
  end

  class TaxonFactory
    include Logging

    def create_samples
      log "Creating taxonomies:"
      taxonomy = Spree::Taxonomy.find_or_create_by_name!('Products')
      taxons = ['Vegetables', 'Fruit', 'Oils', 'Preserves and Sauces', 'Dairy', 'Meat and Fish']
      taxons.each do |taxon_name|
        create_taxon(taxonomy, taxon_name)
      end
    end

    private

    def create_taxon(taxonomy, taxon_name)
      return if Spree::Taxon.where(name: taxon_name).exists?
      log "- #{taxon_name}"
      Spree::Taxon.create!(
        name: taxon_name,
        parent_id: taxonomy.root.id,
        taxonomy_id: taxonomy.id
      )
    end
  end

  class ProductFactory
    include Logging

    def create_samples(enterprises)
      log "Creating products:"
      product_data(enterprises).map do |hash|
        create_product(hash)
      end
    end

    private

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def product_data(enterprises)
      vegetables = Spree::Taxon.find_by_name('Vegetables')
      fruit = Spree::Taxon.find_by_name('Fruit')
      meat = Spree::Taxon.find_by_name('Meat and Fish')
      producers = enterprises.select(&:is_primary_producer)
      distributors = enterprises.select(&:is_distributor)
      [
        {
          name: 'Garlic',
          price: 20.00,
          supplier: producers[0],
          taxons: [vegetables],
          distributor: distributors[0]
        },
        {
          name: 'Fuji Apple',
          price: 5.00,
          supplier: producers[1],
          taxons: [fruit],
          distributor: distributors[0]
        },
        {
          name: 'Beef - 5kg Trays',
          price: 50.00,
          supplier: producers[1],
          taxons: [meat],
          distributor: distributors[0]
        },
        {
          name: 'Carrots',
          price: 3.00,
          supplier: producers[2],
          taxons: [vegetables],
          distributor: distributors[0]
        },
        {
          name: 'Potatoes',
          price: 2.00,
          supplier: producers[2],
          taxons: [vegetables],
          distributor: distributors[0]
        },
        {
          name: 'Tomatoes',
          price: 2.00,
          supplier: producers[2],
          taxons: [vegetables],
          distributor: distributors[0]
        }
      ]
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    def create_product(hash)
      log "- #{hash[:name]}"
      params = hash.merge(
        supplier_id: hash[:supplier].id,
        primary_taxon_id: hash[:taxons].first.id,
        variant_unit: "weight",
        variant_unit_scale: 1,
        unit_value: 1,
        on_demand: true
      )
      create_product_with_distribution(params)
    end

    def create_product_with_distribution(params)
      product = Spree::Product.create_with(params).find_or_create_by_name(params[:name])
      ProductDistribution.create(
        product: product,
        distributor: params[:distributor]
      )
      product
    end
  end

  class InventoryFactory
    include Logging

    def create_samples(products)
      log "Creating inventories"
      marys_shop = Enterprise.find_by_name("Mary's Online Shop")
      products.each do |product|
        create_item(marys_shop, product)
      end
    end

    private

    def create_item(shop, product)
      InventoryItem.create_with(
        enterprise: shop,
        variant: product.variants.first,
        visible: true
      ).find_or_create_by_variant_id(product.variants.first.id)
      create_override(shop, product)
    end

    def create_override(shop, product)
      VariantOverride.create_with(
        variant: product.variants.first,
        hub: shop,
        price: 12,
        count_on_hand: 5
      ).find_or_create_by_variant_id(product.variants.first.id)
    end
  end

  class OrderCycleFactory
    include Logging
    # rubocop:disable Metrics/MethodLength
    def create_samples
      log "Creating order cycles"
      create_order_cycle(
        "Freddy's Farm Shop OC",
        "Freddy's Farm Shop",
        ["Freddy's Farm Shop"],
        ["Freddy's Farm Shop"],
        receival_instructions: "Dear self, don't forget the keys.",
        pickup_time: "the weekend",
        pickup_instructions: "Bring your own shopping bags or boxes."
      )

      create_order_cycle(
        "Fredo's Farm Hub OC",
        "Fredo's Farm Hub",
        ["Fred's Farm", "Fredo's Farm Hub"],
        ["Fredo's Farm Hub"],
        receival_instructions: "Under the shed, please.",
        pickup_time: "Wednesday 2pm",
        pickup_instructions: "Boxes for packaging under the roof."
      )

      create_order_cycle(
        "Mary's Online Shop OC",
        "Mary's Online Shop",
        ["Fred's Farm", "Freddy's Farm Shop", "Fredo's Farm Hub"],
        ["Mary's Online Shop"],
        receival_instructions: "Please shut the gate.",
        pickup_time: "midday"
      )

      create_order_cycle(
        "Multi Shop OC",
        "Mary's Online Shop",
        ["Fred's Farm", "Freddy's Farm Shop", "Fredo's Farm Hub"],
        ["Mary's Online Shop", "Maryse's Private Shop"],
        receival_instructions: "Please shut the gate.",
        pickup_time: "dusk"
      )
    end
    # rubocop:enable Metrics/MethodLength

    private

    def create_order_cycle(name, coordinator_name, supplier_names, distributor_names, data)
      coordinator = Enterprise.find_by_name(coordinator_name)
      return if OrderCycle.active.where(name: name).exists?

      log "- #{name}"
      cycle = create_order_cycle_with_fee(name, coordinator)
      create_exchanges(cycle, supplier_names, distributor_names, data)
    end

    def create_order_cycle_with_fee(name, coordinator)
      cycle = OrderCycle.create!(
        name: name,
        orders_open_at: 1.day.ago,
        orders_close_at: 1.month.from_now,
        coordinator: coordinator
      )
      cycle.coordinator_fees << coordinator.enterprise_fees.first
      cycle
    end

    def create_exchanges(cycle, supplier_names, distributor_names, data)
      suppliers = Enterprise.where(name: supplier_names)
      distributors = Enterprise.where(name: distributor_names)

      incoming = incoming_exchanges(cycle, suppliers, data)
      outgoing = outgoing_exchanges(cycle, distributors, data)
      all_exchanges = incoming + outgoing
      add_products(suppliers, all_exchanges)
    end

    def incoming_exchanges(cycle, suppliers, data)
      suppliers.map do |supplier|
        Exchange.create!(
          order_cycle: cycle,
          sender: supplier,
          receiver: cycle.coordinator,
          incoming: true,
          receival_instructions: data[:receival_instructions]
        )
      end
    end

    def outgoing_exchanges(cycle, distributors, data)
      distributors.map do |distributor|
        Exchange.create!(
          order_cycle: cycle,
          sender: cycle.coordinator,
          receiver: distributor,
          incoming: false,
          pickup_time: data[:pickup_time],
          pickup_instructions: data[:pickup_instructions]
        )
      end
    end

    def add_products(suppliers, exchanges)
      products = suppliers.flat_map(&:supplied_products)
      products.each do |product|
        exchanges.each { |exchange| exchange.variants << product.variants.first }
      end
    end
  end

  class CustomerFactory
    include Logging

    def create_samples(users)
      log "Creating customers"
      jane = users["Jane Customer"]
      maryse_shop = Enterprise.find_by_name("Maryse's Private Shop")
      return if Customer.where(user_id: jane, enterprise_id: maryse_shop).exists?
      log "- #{jane.email}"
      Customer.create!(
        email: jane.email,
        user: jane,
        enterprise: maryse_shop
      )
    end
  end

  class GroupFactory
    include Logging
    include Addressing

    def create_samples
      log "Creating groups"
      return if EnterpriseGroup.where(name: "Producer group").exists?

      create_group(
        name: "Producer group",
        owner: enterprises.first.owner,
        on_front_page: true,
        description: "The seed producers",
        address: "6 Rollings Road, Upper Ferntree Gully, 3156"
      )
    end

    private

    def create_group(params)
      group = EnterpriseGroup.new(params)
      group.address = address(params[:address])
      group.enterprises = enterprises
      group.save!
    end

    def enterprises
      @enterprises ||= Enterprise.where(name: [
        "Fred's Farm",
        "Freddy's Farm Shop",
        "Fredo's Farm Hub"
      ])
    end
  end
end
