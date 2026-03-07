# StoreERP — Store Manager

A Rails-based ERP system for managing paint and hardware stores. Handles products, brands, shade catalogues, organisational setup, and role-based access control.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Framework** | Ruby on Rails 7.1 |
| **Language** | Ruby 3.3.5 |
| **Database** | PostgreSQL 16 |
| **Auth** | Devise + CanCanCan |
| **Background Jobs** | GoodJob |
| **Excel Import/Export** | Roo + Caxlsx |
| **Asset Pipeline** | Sprockets + Importmap |
| **Testing** | Minitest, RSpec, Capybara, Selenium |
| **CI** | CircleCI |

## Getting Started

### Prerequisites

- Ruby 3.3.5 (via rbenv/asdf)
- PostgreSQL 16+
- Chrome (for Selenium feature tests)

### Setup

```bash
# Clone & install
git clone git@github.com:atewary17/store_manager.git
cd store_manager
bundle install

# Database
cp config/database.yml.example config/database.yml   # if applicable
bin/rails db:create db:migrate db:seed

# Start server
bin/rails server
```

Visit `http://localhost:3000`

## Project Structure

```
app/
├── controllers/
│   ├── setup/              # Master data controllers (brands, uoms, products, etc.)
│   └── dashboard_controller.rb
├── models/
│   ├── ability.rb          # CanCanCan authorization rules
│   ├── brand.rb
│   ├── uom.rb
│   ├── product.rb
│   ├── product_category.rb
│   ├── shade_catalogue.rb
│   ├── product_import.rb
│   ├── shade_catalogue_import.rb
│   ├── organisation.rb
│   └── user.rb
└── views/
    └── setup/              # Setup index, form, and show views
```

## Setup / Master Data

All setup screens are restricted to **super_admin** role via CanCanCan.

| Module | Description |
|--------|-------------|
| **Brands** | Paint/product brands (Asian Paints, Berger, etc.) |
| **UOMs** | Units of measure (Litre, Kg, Piece) |
| **Product Categories** | Groups with optional paint-type flag for shade workflow |
| **Products** | Full product catalogue with GST, HSN, MRP |
| **Shade Catalogue** | Shade codes and colour families for paint categories |
| **Imports** | Bulk Excel import for products and shades |

## Authorization

| Role | Setup Access | Dashboard |
|------|-------------|-----------|
| `super_admin` | ✅ Full access | ✅ |
| `owner` | ❌ Denied | ✅ |
| `admin` | ❌ Denied | ✅ |
| `staff` | ❌ Denied | ✅ |

## Testing

### Minitest (Unit + Controller)

```bash
bin/rails test                     # All 189 tests
bin/rails test test/models/        # Model tests only
bin/rails test test/controllers/   # Controller tests only
```

### RSpec + Capybara + Selenium (Feature Specs)

```bash
bundle exec rspec                           # All 41 feature specs (headless)
HEADLESS=false bundle exec rspec            # Visible Chrome (debugging)
bundle exec rspec spec/features/setup/      # Setup features only
```

### Coverage Summary

| Suite | Tests | What's Covered |
|-------|-------|---------------|
| Minitest | 189 tests, 263 assertions | Models (validations, scopes, callbacks, methods), Controllers (CRUD, auth) |
| RSpec | 41 feature specs | Full browser flows: index, search, filter, create, edit, delete, authorization |

## CI / CD

CircleCI pipeline runs on every push:

```
lint ──┬── minitest   (parallel, split by timing)
       ├── rspec      (parallel, Selenium + Chrome)
       └── assets     (precompile check)
```

Config: [`.circleci/config.yml`](.circleci/config.yml)

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `RAILS_MASTER_KEY` | Credentials decryption key |
| `HEADLESS` | Set to `false` for visible Chrome in tests |

## License

Private — All rights reserved.
