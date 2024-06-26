# frozen_string_literal: true

module Idv
  class SendPhoneConfirmationOtp
    attr_reader :telephony_response

    def initialize(user:, idv_session:)
      @user = user
      @idv_session = idv_session
    end

    def call
      otp_rate_limiter.reset_count_and_otp_last_sent_at if user.no_longer_locked_out?

      # The pattern for checking the rate limiter, incrementing, then checking again was introduced
      # in this change: https://github.com/18F/identity-idp/pull/2216
      #
      # This adds protection against a race condition that would result in sending a large number
      # of OTPs and/or needlessly making atomic increments to the rate limit counter if
      # a bad actor sends many requests at the same time.
      #
      return too_many_otp_sends_response if rate_limit_exceeded?
      otp_rate_limiter.increment
      return too_many_otp_sends_response if rate_limit_exceeded?

      send_otp
    end

    def user_locked_out?
      @user_locked_out
    end

    private

    attr_reader :user, :idv_session

    delegate :user_phone_confirmation_session, to: :idv_session
    delegate :phone, :code, :delivery_method, to: :user_phone_confirmation_session

    def too_many_otp_sends_response
      FormResponse.new(
        success: false,
        extra: extra_analytics_attributes,
      )
    end

    def rate_limit_exceeded?
      if otp_rate_limiter.exceeded_otp_send_limit?
        otp_rate_limiter.lock_out_user
        return @user_locked_out = true
      end
      false
    end

    def otp_rate_limiter
      @otp_rate_limiter ||= OtpRateLimiter.new(
        user: user,
        phone: phone,
        phone_confirmed: true,
      )
    end

    def send_otp
      idv_session.user_phone_confirmation_session = user_phone_confirmation_session.regenerate_otp
      @telephony_response = Telephony.send_confirmation_otp(
        otp: code,
        to: phone,
        expiration: TwoFactorAuthenticatable::DIRECT_OTP_VALID_FOR_MINUTES,
        otp_format: I18n.t("telephony.format_type.#{format}"),
        otp_length: I18n.t("telephony.format_length.#{length}"),
        channel: delivery_method,
        domain: IdentityConfig.store.domain_name,
        country_code: parsed_phone.country,
        extra_metadata: {
          area_code: parsed_phone.area_code,
          phone_fingerprint: Pii::Fingerprinter.fingerprint(parsed_phone.e164),
          resend: nil,
        },
      )
      otp_sent_response
    end

    def bucket
      @bucket ||= AbTests::IDV_TEN_DIGIT_OTP.bucket(
        idv_session.user_phone_confirmation_session.user.uuid,
      )
    end

    def format
      return 'digit' if delivery_method == :voice && bucket == :ten_digit_otp

      'character'
    end

    def length
      return 'ten' if delivery_method == :voice && bucket == :ten_digit_otp

      'six'
    end

    def otp_sent_response
      FormResponse.new(
        success: telephony_response.success?, extra: extra_analytics_attributes,
      )
    end

    def extra_analytics_attributes
      attributes = {
        otp_delivery_preference: delivery_method,
        country_code: parsed_phone.country,
        area_code: parsed_phone.area_code,
        phone_fingerprint: Pii::Fingerprinter.fingerprint(parsed_phone.e164),
        rate_limit_exceeded: rate_limit_exceeded?,
        telephony_response: @telephony_response,
      }
      if IdentityConfig.store.ab_testing_idv_ten_digit_otp_enabled
        attributes[:ab_tests] = {
          AbTests::IDV_TEN_DIGIT_OTP.experiment_name => {
            bucket: bucket,
          },
        }
      end

      attributes
    end

    def parsed_phone
      @parsed_phone ||= Phonelib.parse(phone)
    end
  end
end
