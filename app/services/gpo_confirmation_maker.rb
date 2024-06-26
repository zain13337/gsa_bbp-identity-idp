# frozen_string_literal: true

class GpoConfirmationMaker
  class InvalidEntryError < StandardError
    def initialize(reason)
      @reason = reason
      super("InvalidEntryError: #{reason}")
    end
    attr_reader :reason
  end

  def initialize(pii:, service_provider:, profile: nil, profile_id: nil, otp: nil)
    raise ArgumentError 'must have either profile or profile_id' if !profile && !profile_id

    @pii = pii
    @service_provider = service_provider
    @profile = profile
    @profile_id = profile_id
    @otp = otp
  end

  def otp
    @otp ||= generate_otp
  end

  def perform
    begin
      GpoConfirmation.create!(entry: attributes)
    rescue ActiveRecord::RecordInvalid => err
      raise InvalidEntryError.new(err)
    end

    GpoConfirmationCode.create!(
      profile_id: profile&.id || profile_id,
      otp_fingerprint: Pii::Fingerprinter.fingerprint(otp),
    )

    update_proofing_cost
  end

  private

  attr_reader :pii, :service_provider, :profile, :profile_id

  def attributes
    {
      address1: pii[:address1],
      address2: pii[:address2],
      city: pii[:city],
      otp: otp,
      first_name: pii[:first_name],
      last_name: pii[:last_name],
      state: pii[:state],
      zipcode: pii[:zipcode],
      issuer: service_provider&.issuer,
    }
  end

  def generate_otp
    ProfanityDetector.without_profanity do
      # Crockford encoding is 5 bits per character
      Base32::Crockford.encode(SecureRandom.random_number(2 ** (5 * 10)), length: 10)
    end
  end

  def update_proofing_cost
    Db::SpCost::AddSpCost.call(service_provider, :gpo_letter)
  end
end
