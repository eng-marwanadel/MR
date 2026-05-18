# encoding: UTF-8
# pass.rb - بيانات تسجيل الدخول الخاصة بلوحة تحكم التسعير (30 حساب)
# الرابط: https://raw.githubusercontent.com/eng-marwanadel/MR/refs/heads/main/pass.rb

module MHDESIGN
  module PricingAuth
    # قائمة الحسابات (الرقم السري : كلمة المرور)
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

    # التحقق من صحة الرقم السري وكلمة المرور
    def self.authenticate(serial, password)
      return false if serial.nil? || password.nil?
      serial_clean = serial.to_s.strip
      password_clean = password.to_s.strip
      expected = ACCOUNTS[serial_clean]
      return false if expected.nil?
      expected == password_clean
    end

    # التحقق من وجود حساب (اختياري)
    def self.account_exists?(serial)
      ACCOUNTS.key?(serial.to_s.strip)
    end

    # الحصول على الرقم السري (للعرض في الإعدادات)
    def self.get_serial
      "ادخل الرقم السري الخاص بك"
    end
  end
end
