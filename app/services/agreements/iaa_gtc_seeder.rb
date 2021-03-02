module Agreements
  class IaaGtcSeeder < BaseSeeder
    # The core functionality of this class is defined in BaseSeeder

    private

    def record_class
      IaaGtc
    end

    def filename
      'iaa_gtcs.yml'
    end

    def primary_attribute_bundle(config)
      { 'gtc_number' => config['gtc_number'] }
    end

    def process_config(gtc_number, config)
      config['partner_account'] =
        PartnerAccount.find_by!(requesting_agency: config['partner_account'])
      config['iaa_status'] =
        IaaStatus.find_by!(name: config['iaa_status'])

      permitted_attrs =
        %w[mod_number start_date end_date estimated_amount iaa_status partner_account]
      config.slice(*permitted_attrs).merge('gtc_number' => gtc_number)
    end
  end
end
