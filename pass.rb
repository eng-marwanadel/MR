# encoding: UTF-8
# pass.rb - بيانات تسجيل الدخول الخاصة بلوحة تحكم التسعير (نسخة مستقرة)
module MHDESIGN
  module PricingAuth
    # حسابات العملاء (الرقم السري : كلمة المرور)
    ACCOUNTS = {
      "ENG-001" => "pass001",
      "ENG-002" => "pass002",
      "ENG-003" => "pass003",
      "ENG-004" => "pass004",
      "ENG-005" => "pass005",
      "ENG-006" => "pass006",
      "ENG-007" => "pass007",
      "ENG-008" => "pass008",
      "ENG-009" => "pass009",
      "ENG-010" => "pass010",
      "ENG-011" => "pass011",
      "ENG-012" => "pass012",
      "ENG-013" => "pass013",
      "ENG-014" => "pass014",
      "ENG-015" => "pass015",
      "ENG-016" => "pass016",
      "ENG-017" => "pass017",
      "ENG-018" => "pass018",
      "ENG-019" => "pass019",
      "ENG-020" => "pass020",
      "ENG-021" => "pass021",
      "ENG-022" => "pass022",
      "ENG-023" => "pass023",
      "ENG-024" => "pass024",
      "ENG-025" => "pass025",
      "ENG-026" => "pass026",
      "ENG-027" => "pass027",
      "ENG-028" => "pass028",
      "ENG-029" => "pass029",
      "ENG-030" => "pass030"
    }

    def self.authenticate(serial, password)
      # تنظيف المدخلات (إزالة المسافات الزائدة)
      serial_clean = serial.to_s.strip
      password_clean = password.to_s.strip

      # التحقق من وجود الحساب
      expected_password = ACCOUNTS[serial_clean]
      return false if expected_password.nil?

      # مقارنة كلمة المرور
      result = (expected_password == password_clean)
      result
    end

    def self.account_exists?(serial)
      ACCOUNTS.key?(serial.to_s.strip)
    end
  end
end
