module InvoiceScan
  # Everything a stage might need that is not the document itself.
  #
  # Built once per scan by the Runner and passed unchanged to every stage, so
  # engines never reach for globals or reload the prompt themselves.
  Context = Struct.new(
    :supplier_hint,     # String  — raw supplier name from the upload form
    :supplier_profile,  # Suppliers::*::Profile
    :prompt,            # String  — brand-specific prompt text
    :organisation,      # Organisation | nil
    keyword_init: true
  ) do
    def self.build(supplier_hint: nil, organisation: nil)
      new(
        supplier_hint:    supplier_hint,
        supplier_profile: Suppliers::Registry.for(supplier_hint),
        prompt:           InvoiceScan::PromptLoader.for_supplier(supplier_hint),
        organisation:     organisation
      )
    end
  end
end
