# encoding: UTF-8
# pricing.rb - نظام تسعير متكامل للمكتبة MRDESIGN
# يعمل بنظام مصادقة داخلي (يُطلب تعيين الرقم السري وكلمة المرور في أول استخدام)
# لا يعتمد على ملفات خارجية للمصادقة.

module MHDESIGN
  module AdvancedPricing
    # ======================================================================
    # دوال المصادقة الداخلية (تخزين محلي)
    # ======================================================================
    def self.hash_password(pass)
      Digest::SHA256.hexdigest(pass.to_s)
    end

    def self.set_engineer_credentials(serial, password)
      Sketchup.write_default("MHDESIGN_PRICING_AUTH", "serial", serial.to_s.strip)
      Sketchup.write_default("MHDESIGN_PRICING_AUTH", "password_hash", hash_password(password))
    end

    def self.authenticate(serial, password)
      saved_serial = Sketchup.read_default("MHDESIGN_PRICING_AUTH", "serial")
      saved_hash = Sketchup.read_default("MHDESIGN_PRICING_AUTH", "password_hash")
      return false if saved_serial.nil? || saved_serial.empty?
      serial.to_s.strip == saved_serial && hash_password(password) == saved_hash
    end

    def self.is_first_run?
      serial = Sketchup.read_default("MHDESIGN_PRICING_AUTH", "serial")
      serial.nil? || serial.empty?
    end

    def self.update_password(new_password)
      serial = Sketchup.read_default("MHDESIGN_PRICING_AUTH", "serial")
      return false if serial.nil? || serial.empty?
      set_engineer_credentials(serial, new_password)
      true
    end

    def self.get_engineer_serial
      Sketchup.read_default("MHDESIGN_PRICING_AUTH", "serial") || "غير محدد"
    end

    # ======================================================================
    # دوال الخامات
    # ======================================================================
    def self.get_materials
      json = Sketchup.read_default("MHDESIGN", "pricing_materials")
      json && !json.empty? ? JSON.parse(json) : []
    rescue
      []
    end

    def self.save_materials(materials)
      Sketchup.write_default("MHDESIGN", "pricing_materials", materials.to_json)
    end

    def self.add_material(code, name, type, price, waste, notes)
      mats = get_materials
      mats << { "code" => code, "name" => name, "type" => type, "price_per_sqm" => price.to_f, "waste" => waste.to_i, "notes" => notes.to_s }
      save_materials(mats)
    end

    def self.update_material(code, price, waste, notes)
      mats = get_materials
      mat = mats.find { |m| m["code"] == code }
      return false unless mat
      mat["price_per_sqm"] = price.to_f
      mat["waste"] = waste.to_i
      mat["notes"] = notes.to_s
      save_materials(mats)
      true
    end

    def self.delete_material(code)
      mats = get_materials.reject { |m| m["code"] == code }
      save_materials(mats)
    end

    # ======================================================================
    # دوال الأكسسوارات
    # ======================================================================
    def self.get_accessories
      json = Sketchup.read_default("MHDESIGN", "pricing_accessories")
      json && !json.empty? ? JSON.parse(json) : []
    rescue
      []
    end

    def self.save_accessories(accessories)
      Sketchup.write_default("MHDESIGN", "pricing_accessories", accessories.to_json)
    end

    def self.add_accessory(code, name, price, notes)
      acc = get_accessories
      acc << { "code" => code, "name" => name, "price" => price.to_f, "notes" => notes.to_s }
      save_accessories(acc)
    end

    def self.update_accessory(code, price, notes)
      acc = get_accessories
      a = acc.find { |x| x["code"] == code }
      return false unless a
      a["price"] = price.to_f
      a["notes"] = notes.to_s
      save_accessories(acc)
      true
    end

    def self.delete_accessory(code)
      acc = get_accessories.reject { |a| a["code"] == code }
      save_accessories(acc)
    end

    # ======================================================================
    # دوال إعدادات الوحدات
    # ======================================================================
    def self.get_unit_pricing_config(unit_code)
      key = "unit_pricing_#{unit_code}"
      json = Sketchup.read_default("MHDESIGN", key)
      json && !json.empty? ? JSON.parse(json) : {}
    rescue
      {}
    end

    def self.save_unit_pricing_config(unit_code, config)
      key = "unit_pricing_#{unit_code}"
      Sketchup.write_default("MHDESIGN", key, config.to_json)
    end

    # ======================================================================
    # جلب جميع الوحدات من مكتبة MHDESIGN (ملفات JSON الأربعة)
    # ======================================================================
    def self.get_all_units_from_library
      all = []
      [["A","A"], ["A","B"], ["B","B"], ["B","A"]].each do |lower, upper|
        list = MHDESIGN.load_components_for_combo(lower, upper)
        list.each do |unit|
          all << unit.merge({ lower_mode: lower, upper_mode: upper })
        end
      end
      all.uniq { |u| u[:url] }
    rescue
      []
    end

    # ======================================================================
    # قراءة أبعاد المكون المحدد في SketchUp
    # ======================================================================
    def self.get_selected_component_dimensions
      model = Sketchup.active_model
      sel = model.selection
      return nil if sel.empty?
      instance = sel.first
      return nil unless instance.is_a?(Sketchup::ComponentInstance)
      bounds = instance.bounds
      { width: (bounds.width * 100).round(1), height: (bounds.height * 100).round(1), depth: (bounds.depth * 100).round(1) }
    rescue
      nil
    end

    # ======================================================================
    # حساب سعر الوحدة بناءً على الإعدادات والأبعاد المدخلة
    # ======================================================================
    def self.calculate_unit_price(unit_code, width_cm, height_cm, material_code = nil, extra_accessories = [], tax_rate = 0)
      config = get_unit_pricing_config(unit_code)
      return { error: "لا توجد إعدادات تسعير لهذه الوحدة" } if config.empty?

      pricing_type = config["pricing_type"] || "fixed_price"
      base_price = config["base_price"].to_f
      custom_formula = config["custom_formula"].to_s
      default_material = config["default_material"]

      # تحديد الخامة
      material = nil
      if material_code && !material_code.empty?
        materials = get_materials
        material = materials.find { |m| m["code"] == material_code }
      end
      if material.nil? && default_material && !default_material.empty?
        material = get_materials.find { |m| m["code"] == default_material }
      end

      material_price_per_unit = material ? material["price_per_sqm"].to_f : 0.0
      material_waste = material ? material["waste"].to_f / 100.0 : 0.0

      width_m = width_cm.to_f / 100.0
      height_m = height_cm.to_f / 100.0
      area_sqm = (width_m * height_m).round(4)
      length_m = width_m

      material_cost = 0.0
      case pricing_type
      when "square_meter"
        material_cost = area_sqm * material_price_per_unit * (1 + material_waste)
      when "linear_meter"
        material_cost = length_m * material_price_per_unit * (1 + material_waste)
      when "fixed_price"
        material_cost = base_price
      when "custom_formula"
        begin
          material_cost = eval(custom_formula) rescue base_price
        rescue
          material_cost = base_price
        end
      else
        material_cost = base_price
      end

      # الأكسسوارات المرتبطة
      linked_accessories = config["linked_accessories"] || []
      linked_cost = 0.0
      all_accessories = get_accessories
      linked_accessories.each do |link|
        acc = all_accessories.find { |a| a["code"] == link["code"] }
        linked_cost += acc["price"].to_f * link["quantity"].to_i if acc
      end

      # الأكسسوارات الإضافية
      extra_cost = 0.0
      extra_accessories.each do |acc_code|
        acc = all_accessories.find { |a| a["code"] == acc_code }
        extra_cost += acc["price"].to_f if acc
      end

      subtotal = material_cost + linked_cost + extra_cost
      tax = subtotal * (tax_rate / 100.0)
      total = subtotal + tax

      {
        material_cost: material_cost.round(2),
        linked_accessories_cost: linked_cost.round(2),
        extra_accessories_cost: extra_cost.round(2),
        subtotal: subtotal.round(2),
        tax: tax.round(2),
        total: total.round(2),
        area_sqm: area_sqm,
        length_m: length_m,
        used_material: material ? material["name"] : "غير محدد",
        pricing_type: pricing_type
      }
    end

    # ======================================================================
    # دوال التقارير (تصدير CSV)
    # ======================================================================
    def self.export_units_report
      units = get_all_units_from_library
      csv = "الاسم,الرابط,نوع التسعير,السعر الأساسي,الخامة الافتراضية,العرض الافتراضي (سم),الارتفاع الافتراضي (سم),الأكسسوارات المرتبطة\n"
      units.each do |u|
        cfg = get_unit_pricing_config(u[:url])
        linked = (cfg["linked_accessories"] || []).map { |l| "#{l['code']}:#{l['quantity']}" }.join("; ")
        csv += "#{u[:name]},#{u[:url]},#{cfg['pricing_type'] || 'fixed'},#{cfg['base_price'] || 0},#{cfg['default_material'] || ''},#{cfg['default_width'] || 60},#{cfg['default_height'] || 80},#{linked}\n"
      end
      filename = File.join(Dir.tmpdir, "units_pricing_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv")
      File.write(filename, csv)
      filename
    end

    def self.export_materials_report
      mats = get_materials
      csv = "الكود,الاسم,النوع,السعر,الهالك %,ملاحظات\n"
      mats.each do |m|
        csv += "#{m['code']},#{m['name']},#{m['type']},#{m['price_per_sqm']},#{m['waste']},#{m['notes']}\n"
      end
      filename = File.join(Dir.tmpdir, "materials_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv")
      File.write(filename, csv)
      filename
    end

    def self.export_accessories_report
      acc = get_accessories
      csv = "الكود,الاسم,السعر,ملاحظات\n"
      acc.each do |a|
        csv += "#{a['code']},#{a['name']},#{a['price']},#{a['notes']}\n"
      end
      filename = File.join(Dir.tmpdir, "accessories_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv")
      File.write(filename, csv)
      filename
    end

    def self.reset_all_data
      Sketchup.write_default("MHDESIGN", "pricing_materials", nil)
      Sketchup.write_default("MHDESIGN", "pricing_accessories", nil)
      UI.messagebox("✅ تم مسح بيانات الخامات والأكسسوارات. إعدادات الوحدات لم تتغير.")
    end

    # ======================================================================
    # فتح لوحة التحكم الرئيسية
    # ======================================================================
    def self.open_dashboard
      # أول مرة: تعيين بيانات المهندس
      if is_first_run?
        prompts = ["🔐 الرقم السري (مثل: ENG-001)", "🔑 كلمة المرور", "تأكيد كلمة المرور"]
        defaults = ["", "", ""]
        input = UI.inputbox(prompts, defaults, "⚙️ الإعدادات الأولية لنظام التسعير - #{MHDESIGN::DISPLAY_NAME}")
        return unless input
        serial, pass, confirm = input
        if serial.to_s.strip.empty? || pass.to_s.empty? || pass != confirm
          UI.messagebox("❌ يجب إدخال رقم سري وكلمة مرور متطابقة.")
          return
        end
        set_engineer_credentials(serial, pass)
        UI.messagebox("✅ تم حفظ بيانات المهندس. يمكنك الآن الدخول.")
      end

      # نافذة تسجيل الدخول
      attempts = 0
      logged_in = false
      while !logged_in && attempts < 3
        prompts = ["الرقم السري", "كلمة المرور"]
        defaults = ["", ""]
        input = UI.inputbox(prompts, defaults, "🔐 دخول المهندس - #{MHDESIGN::DISPLAY_NAME}")
        break unless input
        if authenticate(input[0], input[1])
          logged_in = true
        else
          attempts += 1
          UI.messagebox("❌ بيانات غير صحيحة. تبقى #{3 - attempts} محاولات.")
        end
      end
      return unless logged_in

      # تحميل البيانات الافتراضية إذا كانت الجداول فارغة
      if get_materials.empty?
        default_materials = [
          { "code" => "MAT-001", "name" => "MDF أبيض", "type" => "square_meter", "price_per_sqm" => 250.0, "waste" => 5, "notes" => "سمك 16 مم" },
          { "code" => "MAT-002", "name" => "خشب زان", "type" => "square_meter", "price_per_sqm" => 420.0, "waste" => 10, "notes" => "طبيعي" },
          { "code" => "MAT-003", "name" => "أكريليك لامع", "type" => "square_meter", "price_per_sqm" => 580.0, "waste" => 8, "notes" => "ألوان" },
          { "code" => "MAT-004", "name" => "ألومنيوم (متر طولي)", "type" => "linear_meter", "price_per_sqm" => 120.0, "waste" => 3, "notes" => "مقاطع" }
        ]
        save_materials(default_materials)
      end

      if get_accessories.empty?
        default_accessories = [
          { "code" => "ACC-001", "name" => "مقبض نحاس", "price" => 90.0, "notes" => "لون ذهبي" },
          { "code" => "ACC-002", "name" => "رف زجاج", "price" => 150.0, "notes" => "سمك 8 مم" },
          { "code" => "ACC-003", "name" => "ديكور إضاءة LED", "price" => 220.0, "notes" => "شريط 1 متر" }
        ]
        save_accessories(default_accessories)
      end

      # قائمة الوحدات (للاستخدام داخل JavaScript)
      all_units = get_all_units_from_library

      # إنشاء نافذة HtmlDialog
      dlg = UI::HtmlDialog.new(
        dialog_title: "#{MHDESIGN::DISPLAY_NAME} - نظام التسعير المتكامل (مهندس: #{get_engineer_serial})",
        preferences_key: "mhdesign_pricing_pro_dialog",
        scrollable: true,
        resizable: true,
        width: 1400,
        height: 850,
        style: UI::HtmlDialog::STYLE_DIALOG
      )

      html = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>نظام التسعير المتقدم - #{MHDESIGN::DISPLAY_NAME}</title>
          <link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@400;700&display=swap" rel="stylesheet">
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font-family: 'Tajawal', sans-serif; direction: rtl; background: #f0f4f8; padding: 24px; color: #1e2a3a; }
            .dashboard { max-width: 1600px; margin: 0 auto; }
            h1 { font-size: 28px; margin-bottom: 24px; border-right: 6px solid #2e7d32; padding-right: 20px; display: flex; align-items: center; gap: 12px; }
            .tabs { display: flex; gap: 8px; border-bottom: 2px solid #cfdfed; margin-bottom: 28px; flex-wrap: wrap; }
            .tab-btn { background: #e4ecf3; border: none; padding: 10px 28px; font-size: 16px; font-weight: bold; border-radius: 40px 40px 0 0; cursor: pointer; transition: 0.2s; color: #2c3e4e; }
            .tab-btn.active { background: #2e7d32; color: white; box-shadow: 0 -2px 6px rgba(0,0,0,0.1); }
            .tab-pane { display: none; animation: fade 0.2s ease; }
            .tab-pane.active { display: block; }
            @keyframes fade { from { opacity:0; transform:translateY(8px);} to { opacity:1; transform:translateY(0);} }
            .toolbar { margin-bottom: 20px; display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
            .btn { background: white; border: 1px solid #cbd5e1; padding: 8px 20px; border-radius: 40px; font-family: 'Tajawal', sans-serif; font-weight: bold; cursor: pointer; transition: 0.15s; font-size: 13px; }
            .btn-primary { background: #2e7d32; border-color: #1b5e20; color: white; }
            .btn-primary:hover { background: #1b5e20; }
            .btn-danger { background: #c62828; color: white; border-color: #b71c1c; }
            .btn-danger:hover { background: #b71c1c; }
            .btn-sm { padding: 4px 12px; font-size: 12px; }
            .search { padding: 8px 14px; border: 1px solid #cbd5e1; border-radius: 40px; width: 260px; }
            table { width: 100%; border-collapse: collapse; background: white; border-radius: 20px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.05); }
            th, td { padding: 12px 12px; text-align: right; border-bottom: 1px solid #e2edf2; }
            th { background: #eef3fa; color: #1f3b4c; }
            tr:hover td { background: #f9fdfe; }
            .price { font-weight: bold; color: #2e7d32; }
            .form-row { display: flex; gap: 20px; margin-bottom: 18px; flex-wrap: wrap; align-items: flex-end; }
            .form-group { display: flex; flex-direction: column; gap: 6px; min-width: 160px; }
            .form-group label { font-weight: bold; font-size: 13px; color: #2c5a74; }
            input, select, textarea { padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 16px; background: white; }
            .result-box { background: #eaf7ea; border-right: 6px solid #2e7d32; padding: 20px; border-radius: 20px; margin-top: 20px; }
            .result-line { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #c8e0c8; }
            .total { font-size: 24px; font-weight: bold; color: #1b5e20; margin-top: 12px; }
            .footer { font-size: 12px; color: #7a8e9e; margin-top: 40px; text-align: center; border-top: 1px solid #cfdfed; padding-top: 20px; }
            .settings-group { background: white; border-radius: 20px; padding: 20px; margin-bottom: 20px; }
          </style>
        </head>
        <body>
          <div class="dashboard">
            <h1>💰 نظام التسعير المتقدم - #{MHDESIGN::DISPLAY_NAME}</h1>
            <div class="tabs">
              <button class="tab-btn active" data-tab="materials">🧱 الخامات</button>
              <button class="tab-btn" data-tab="accessories">🔩 الأكسسوارات</button>
              <button class="tab-btn" data-tab="units">🧩 إعدادات الوحدات</button>
              <button class="tab-btn" data-tab="calculator">🧮 الحاسبة الذكية</button>
              <button class="tab-btn" data-tab="reports">📊 التقارير</button>
              <button class="tab-btn" data-tab="settings">⚙️ الإعدادات</button>
            </div>
            <div id="tab-materials" class="tab-pane active">جاري تحميل الخامات...</div>
            <div id="tab-accessories" class="tab-pane">جاري تحميل الأكسسوارات...</div>
            <div id="tab-units" class="tab-pane">جاري تحميل الوحدات...</div>
            <div id="tab-calculator" class="tab-pane">جاري تجهيز الحاسبة...</div>
            <div id="tab-reports" class="tab-pane">جاري تجهيز التقارير...</div>
            <div id="tab-settings" class="tab-pane">جاري تجهيز الإعدادات...</div>
            <div class="footer">تم تصميم نظام التسعير المتقدم خصيصاً لمكتبة #{MHDESIGN::DISPLAY_NAME}</div>
          </div>
          <script>
            let currentUnitCode = "";
            function escapeHtml(str) { return (str||"").replace(/[&<>]/g, function(m){ if(m==='&') return '&amp;'; if(m==='<') return '&lt;'; if(m==='>') return '&gt;'; return m;}); }
            document.querySelectorAll('.tab-btn').forEach(btn => {
              btn.addEventListener('click', function() {
                document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
                this.classList.add('active');
                const tabId = this.dataset.tab;
                document.querySelectorAll('.tab-pane').forEach(pane => pane.classList.remove('active'));
                document.getElementById(`tab-${tabId}`).classList.add('active');
                if (tabId === 'materials') sketchup.getMaterialsData();
                if (tabId === 'accessories') sketchup.getAccessoriesData();
                if (tabId === 'units') sketchup.getUnitsListData();
                if (tabId === 'calculator') sketchup.initCalculator();
                if (tabId === 'reports') sketchup.initReports();
                if (tabId === 'settings') sketchup.initSettings();
              });
            });
            sketchup.getMaterialsData();
            sketchup.getAccessoriesData();
            sketchup.getUnitsListData();
          </script>
        </body>
        </html>
      HTML

      dlg.set_html(html)

      # ======================================================================
      # Callbacks الخامات
      # ======================================================================
      dlg.add_action_callback("getMaterialsData") do |_|
        materials = get_materials
        search_html = '<div class="toolbar"><input type="text" id="searchMaterials" class="search" placeholder="بحث في الخامات..."><button class="btn btn-primary" onclick="addMaterial()">➕ إضافة خامة</button></div>'
        table_html = '<table><thead><tr><th>الكود</th><th>الاسم</th><th>النوع</th><th>السعر</th><th>الهالك %</th><th>ملاحظات</th><th></th></tr></thead><tbody id="materialsTbody"></tbody></table>'
        dlg.execute_script("document.getElementById('tab-materials').innerHTML = #{search_html.to_json} + #{table_html.to_json};")
        materials.each do |m|
          row = "<tr><td>#{m['code']}</td><td>#{m['name']}</td><td>#{m['type']}</td><td class='price'>#{m['price_per_sqm']}</td><td>#{m['waste']}%</td><td>#{m['notes']}</td><td><button class='btn btn-sm' onclick='editMaterial(\"#{m['code']}\")'>✏️</button> <button class='btn btn-sm btn-danger' onclick='deleteMaterial(\"#{m['code']}\")'>🗑️</button></td></tr>"
          dlg.execute_script("document.getElementById('materialsTbody').innerHTML += #{row.to_json};")
        end
        dlg.execute_script("document.getElementById('searchMaterials')?.addEventListener('input', function(e){ let val = e.target.value.toLowerCase(); document.querySelectorAll('#materialsTbody tr').forEach(row=>{ row.style.display = row.innerText.toLowerCase().includes(val)?'':'none'; }); });")
      end

      dlg.add_action_callback("addMaterial") do |_|
        prompts = ["الكود (مثل MAT-005)", "الاسم", "النوع (square_meter/linear_meter/piece)", "السعر لكل وحدة", "الهالك %", "ملاحظات"]
        defaults = ["", "", "square_meter", "0", "0", ""]
        input = UI.inputbox(prompts, defaults, "إضافة خامة جديدة")
        if input && input[0].to_s.strip != ""
          add_material(input[0], input[1], input[2], input[3].to_f, input[4].to_i, input[5])
          dlg.execute_script("sketchup.getMaterialsData();")
        end
      end

      dlg.add_action_callback("editMaterial") do |_, code|
        mats = get_materials
        mat = mats.find { |m| m["code"] == code }
        if mat
          prompts = ["السعر", "الهالك %", "ملاحظات"]
          defaults = [mat["price_per_sqm"].to_s, mat["waste"].to_s, mat["notes"].to_s]
          input = UI.inputbox(prompts, defaults, "تعديل خامة: #{mat['name']}")
          if input
            update_material(code, input[0].to_f, input[1].to_i, input[2])
            dlg.execute_script("sketchup.getMaterialsData();")
          end
        end
      end

      dlg.add_action_callback("deleteMaterial") do |_, code|
        if UI.messagebox("هل تريد حذف الخامة #{code}؟", MB_YESNO) == IDYES
          delete_material(code)
          dlg.execute_script("sketchup.getMaterialsData();")
        end
      end

      # ======================================================================
      # Callbacks الأكسسوارات
      # ======================================================================
      dlg.add_action_callback("getAccessoriesData") do |_|
        accessories = get_accessories
        html = '<div class="toolbar"><input type="text" id="searchAcc" class="search" placeholder="بحث..."><button class="btn btn-primary" onclick="addAccessory()">➕ إضافة أكسسوار</button></div><table><thead><tr><th>الكود</th><th>الاسم</th><th>السعر</th><th>ملاحظات</th><th></th></tr></thead><tbody id="accTbody"></tbody></table>'
        dlg.execute_script("document.getElementById('tab-accessories').innerHTML = #{html.to_json};")
        accessories.each do |a|
          row = "<tr><td>#{a['code']}</td><td>#{a['name']}</td><td class='price'>#{a['price']}</td><td>#{a['notes']}</td><td><button class='btn btn-sm' onclick='editAccessory(\"#{a['code']}\")'>✏️</button> <button class='btn btn-sm btn-danger' onclick='deleteAccessory(\"#{a['code']}\")'>🗑️</button></td></tr>"
          dlg.execute_script("document.getElementById('accTbody').innerHTML += #{row.to_json};")
        end
        dlg.execute_script("document.getElementById('searchAcc')?.addEventListener('input', function(e){ let val = e.target.value.toLowerCase(); document.querySelectorAll('#accTbody tr').forEach(row=>{ row.style.display = row.innerText.toLowerCase().includes(val)?'':'none'; }); });")
      end

      dlg.add_action_callback("addAccessory") do |_|
        prompts = ["الكود (مثل ACC-010)", "الاسم", "السعر", "ملاحظات"]
        defaults = ["", "", "0", ""]
        input = UI.inputbox(prompts, defaults, "إضافة أكسسوار")
        if input && input[0].to_s.strip != ""
          add_accessory(input[0], input[1], input[2].to_f, input[3])
          dlg.execute_script("sketchup.getAccessoriesData();")
        end
      end

      dlg.add_action_callback("editAccessory") do |_, code|
        acc = get_accessories
        a = acc.find { |x| x["code"] == code }
        if a
          prompts = ["السعر", "ملاحظات"]
          defaults = [a["price"].to_s, a["notes"].to_s]
          input = UI.inputbox(prompts, defaults, "تعديل أكسسوار: #{a['name']}")
          if input
            update_accessory(code, input[0].to_f, input[1])
            dlg.execute_script("sketchup.getAccessoriesData();")
          end
        end
      end

      dlg.add_action_callback("deleteAccessory") do |_, code|
        if UI.messagebox("هل تريد حذف الأكسسوار #{code}؟", MB_YESNO) == IDYES
          delete_accessory(code)
          dlg.execute_script("sketchup.getAccessoriesData();")
        end
      end

      # ======================================================================
      # Callbacks الوحدات
      # ======================================================================
      dlg.add_action_callback("getUnitsListData") do |_|
        units = get_all_units_from_library
        select_html = '<div class="toolbar"><select id="unitSelect" style="width:350px;"><option value="">-- اختر وحدة --</option>'
        units.each { |u| select_html += "<option value='#{u[:url]}'>#{u[:name]}</option>" }
        select_html += '</select><button class="btn btn-primary" onclick="loadUnitConfig()">تحميل الإعدادات</button><button class="btn" onclick="saveUnitConfig()">💾 حفظ إعدادات الوحدة</button></div>'
        panel_html = '<div id="unitConfigPanel" style="background:white; padding:24px; border-radius:24px; margin-top:20px;"><div class="form-row"><div class="form-group"><label>نوع التسعير</label><select id="pricingType"><option value="square_meter">متر مربع</option><option value="linear_meter">متر طولي</option><option value="fixed_price">سعر ثابت</option><option value="custom_formula">معادلة مخصصة</option></select></div><div class="form-group"><label>السعر الأساسي</label><input type="number" id="basePrice" step="0.01"></div><div class="form-group"><label>المعادلة المخصصة</label><input type="text" id="customFormula" placeholder="width * height * 0.05 + 200"></div></div><div class="form-row"><div class="form-group"><label>الخامة الافتراضية</label><select id="defaultMaterial"></select></div><div class="form-group"><label>العرض الافتراضي (سم)</label><input type="number" id="defaultWidth"></div><div class="form-group"><label>الارتفاع الافتراضي (سم)</label><input type="number" id="defaultHeight"></div></div><div class="form-group"><label>الأكسسوارات المرتبطة (كود:الكمية مفصولة بفاصلة)</label><input type="text" id="linkedAccessories" placeholder="ACC-001:2, ACC-002:1"></div></div>'
        dlg.execute_script("document.getElementById('tab-units').innerHTML = #{select_html.to_json} + #{panel_html.to_json};")
        materials = get_materials
        opts = '<option value="">-- بدون خامة --</option>' + materials.map { |m| "<option value='#{m['code']}'>#{m['name']}</option>" }.join('')
        dlg.execute_script("document.getElementById('defaultMaterial').innerHTML = '#{opts.gsub("'", "\\'")}';")
      end

      dlg.add_action_callback("loadUnitConfig") do |_, url|
        config = get_unit_pricing_config(url)
        dlg.execute_script("document.getElementById('pricingType').value = '#{config['pricing_type'] || 'fixed_price'}';")
        dlg.execute_script("document.getElementById('basePrice').value = '#{config['base_price'] || 0}';")
        dlg.execute_script("document.getElementById('customFormula').value = '#{(config['custom_formula'] || '').gsub("'", "\\'")}';")
        dlg.execute_script("document.getElementById('defaultWidth').value = '#{config['default_width'] || 60}';")
        dlg.execute_script("document.getElementById('defaultHeight').value = '#{config['default_height'] || 80}';")
        dlg.execute_script("document.getElementById('defaultMaterial').value = '#{config['default_material'] || ''}';")
        linked = (config['linked_accessories'] || []).map { |l| "#{l['code']}:#{l['quantity']}" }.join(', ')
        dlg.execute_script("document.getElementById('linkedAccessories').value = '#{linked.gsub("'", "\\'")}';")
        dlg.execute_script("currentUnitCode = '#{url.gsub("'", "\\'")}';")
      end

      dlg.add_action_callback("saveUnitConfig") do |_, url, config_json|
        config = JSON.parse(config_json)
        save_unit_pricing_config(url, config)
        UI.messagebox("✅ تم حفظ إعدادات الوحدة.")
      end

      # ======================================================================
      # Callbacks الحاسبة الذكية
      # ======================================================================
      dlg.add_action_callback("initCalculator") do |_|
        units = get_all_units_from_library
        select_html = '<div class="toolbar"><select id="calcUnitSelect" style="width:350px;"><option value="">-- اختر وحدة --</option>'
        units.each { |u| select_html += "<option value='#{u[:url]}'>#{u[:name]}</option>" }
        select_html += '</select><button class="btn btn-primary" onclick="loadUnitToCalc()">تحميل الإعدادات</button><button class="btn" id="getSelectedDimBtn">📏 استخدم المكون المحدد</button></div>'
        form_html = '<div style="background:white; padding:24px; border-radius:24px;"><div class="form-row"><div class="form-group"><label>العرض (سم)</label><input type="number" id="calcWidth" step="0.1"></div><div class="form-group"><label>الارتفاع (سم)</label><input type="number" id="calcHeight" step="0.1"></div><div class="form-group"><label>الخامة</label><select id="calcMaterial"></select></div></div><div class="form-group"><label>أكسسوارات إضافية (Ctrl لاختيار متعدد)</label><select id="extraAccessories" multiple size="4"></select></div><div class="toolbar"><button class="btn btn-primary" onclick="calculatePrice()">💰 حساب السعر</button><button class="btn" onclick="applyPriceToUnit()">✅ تطبيق السعر على الوحدة</button></div><div id="calcResult" class="result-box" style="display:none;"></div></div>'
        dlg.execute_script("document.getElementById('tab-calculator').innerHTML = #{select_html.to_json} + #{form_html.to_json};")
        materials = get_materials
        mat_opts = materials.map { |m| "<option value='#{m['code']}'>#{m['name']}</option>" }.join('')
        dlg.execute_script("document.getElementById('calcMaterial').innerHTML = '#{mat_opts.gsub("'", "\\'")}';")
        acc_opts = get_accessories.map { |a| "<option value='#{a['code']}'>#{a['name']} (#{a['price']} ج.م)</option>" }.join('')
        dlg.execute_script("document.getElementById('extraAccessories').innerHTML = '#{acc_opts.gsub("'", "\\'")}';")
        dlg.execute_script("document.getElementById('getSelectedDimBtn').addEventListener('click', function(){ sketchup.getSelectedDimensions(); });")
      end

      dlg.add_action_callback("loadUnitToCalc") do |_, url|
        config = get_unit_pricing_config(url)
        dlg.execute_script("document.getElementById('calcWidth').value = '#{config['default_width'] || 60}';")
        dlg.execute_script("document.getElementById('calcHeight').value = '#{config['default_height'] || 80}';")
        dlg.execute_script("document.getElementById('calcMaterial').value = '#{config['default_material'] || ''}';")
        dlg.execute_script("currentUnitCode = '#{url.gsub("'", "\\'")}';")
      end

      dlg.add_action_callback("calculatePrice") do |_, url, w, h, mat_code, extras_json, tax_rate|
        extras = JSON.parse(extras_json) rescue []
        tax = tax_rate.to_f
        result = calculate_unit_price(url, w.to_f, h.to_f, mat_code, extras, tax)
        if result[:error]
          dlg.execute_script("alert('#{result[:error]}');")
        else
          result_html = "<div class='result-line'><span>💰 سعر الخامة:</span><span>#{result[:material_cost]} ج.م</span></div>
                         <div class='result-line'><span>🔗 الأكسسوارات المرتبطة:</span><span>#{result[:linked_accessories_cost]} ج.م</span></div>
                         <div class='result-line'><span>➕ أكسسوارات إضافية:</span><span>#{result[:extra_accessories_cost]} ج.م</span></div>
                         <div class='result-line'><span>📦 المجموع الفرعي:</span><span>#{result[:subtotal]} ج.م</span></div>
                         <div class='result-line'><span>🧾 الضريبة (#{tax}%):</span><span>#{result[:tax]} ج.م</span></div>
                         <div class='total'>💰 الإجمالي النهائي: #{result[:total]} ج.م</div>
                         <small>(المساحة: #{result[:area_sqm]} م² | الطول: #{result[:length_m]} م | الخامة: #{result[:used_material]})</small>"
          dlg.execute_script("document.getElementById('calcResult').innerHTML = #{result_html.to_json}; document.getElementById('calcResult').style.display='block';")
        end
      end

      dlg.add_action_callback("applyPriceToUnit") do |_, url, price|
        config = get_unit_pricing_config(url)
        config['base_price'] = price.to_f
        config['pricing_type'] = 'fixed_price'
        save_unit_pricing_config(url, config)
        UI.messagebox("✅ تم حفظ السعر #{price} ج.م كسعر ثابت للوحدة.")
      end

      dlg.add_action_callback("getSelectedDimensions") do |_|
        dims = get_selected_component_dimensions
        if dims
          dlg.execute_script("document.getElementById('calcWidth').value = #{dims[:width]}; document.getElementById('calcHeight').value = #{dims[:height]};")
        else
          dlg.execute_script("alert('لم يتم تحديد أي مكون أو لا يمكن قراءة أبعاده');")
        end
      end

      # ======================================================================
      # Callbacks التقارير
      # ======================================================================
      dlg.add_action_callback("initReports") do |_|
        html = '<div class="toolbar"><button class="btn btn-primary" onclick="exportUnits()">📄 تصدير تقرير الوحدات (CSV)</button><button class="btn btn-primary" onclick="exportMaterials()">📄 تصدير تقرير الخامات (CSV)</button><button class="btn btn-primary" onclick="exportAccessories()">📄 تصدير تقرير الأكسسوارات (CSV)</button><button class="btn btn-danger" onclick="resetData()">⚠️ إعادة ضبط البيانات</button></div>'
        dlg.execute_script("document.getElementById('tab-reports').innerHTML = #{html.to_json};")
        dlg.execute_script("window.exportUnits = function() { sketchup.exportUnitsReport(); };")
        dlg.execute_script("window.exportMaterials = function() { sketchup.exportMaterialsReport(); };")
        dlg.execute_script("window.exportAccessories = function() { sketchup.exportAccessoriesReport(); };")
        dlg.execute_script("window.resetData = function() { if(confirm('سيتم مسح كل الخامات والأكسسوارات. هل أنت متأكد؟')) sketchup.resetAllPricingData(); };")
      end

      dlg.add_action_callback("exportUnitsReport") do |_|
        file = export_units_report
        UI.openURL("file://#{file}")
        UI.messagebox("تم إنشاء التقرير: #{file}")
      end

      dlg.add_action_callback("exportMaterialsReport") do |_|
        file = export_materials_report
        UI.openURL("file://#{file}")
        UI.messagebox("تم إنشاء التقرير: #{file}")
      end

      dlg.add_action_callback("exportAccessoriesReport") do |_|
        file = export_accessories_report
        UI.openURL("file://#{file}")
        UI.messagebox("تم إنشاء التقرير: #{file}")
      end

      dlg.add_action_callback("resetAllPricingData") do |_|
        reset_all_data
        dlg.execute_script("sketchup.getMaterialsData(); sketchup.getAccessoriesData();")
      end

      # ======================================================================
      # Callbacks الإعدادات
      # ======================================================================
      dlg.add_action_callback("initSettings") do |_|
        html = '<div class="settings-group"><h3>🔐 تغيير كلمة مرور المهندس</h3><div class="form-row"><div class="form-group"><label>كلمة المرور الجديدة</label><input type="password" id="newPass"></div><div class="form-group"><label>تأكيد كلمة المرور</label><input type="password" id="confirmPass"></div><button class="btn btn-primary" id="changePassBtn">تغيير</button></div></div>'
        html += '<div class="settings-group"><h3>🧾 إعدادات الضريبة والعملة</h3><div class="form-row"><div class="form-group"><label>نسبة الضريبة (%)</label><input type="number" id="taxRate" step="0.1" value="0"></div><div class="form-group"><label>رمز العملة</label><input type="text" id="currencySymbol" value="ج.م"></div><button class="btn btn-primary" id="saveTaxBtn">حفظ الإعدادات</button></div></div>'
        html += '<div class="settings-group"><h3>ℹ️ معلومات النظام</h3><p>الرقم السري الحالي: ' + get_engineer_serial + '</p></div>'
        dlg.execute_script("document.getElementById('tab-settings').innerHTML = #{html.to_json};")
        tax = Sketchup.read_default("MHDESIGN_PRICING", "tax_rate") || "0"
        currency = Sketchup.read_default("MHDESIGN_PRICING", "currency_symbol") || "ج.م"
        dlg.execute_script("document.getElementById('taxRate').value = '#{tax}';")
        dlg.execute_script("document.getElementById('currencySymbol').value = '#{currency}';")
        dlg.execute_script("document.getElementById('changePassBtn').addEventListener('click', function(){ let p = document.getElementById('newPass').value; let c = document.getElementById('confirmPass').value; if(p && p===c) sketchup.changePassword(p); else alert('كلمتا المرور غير متطابقتين'); });")
        dlg.execute_script("document.getElementById('saveTaxBtn').addEventListener('click', function(){ let tax = document.getElementById('taxRate').value; let cur = document.getElementById('currencySymbol').value; sketchup.saveTaxCurrency(tax, cur); alert('تم حفظ الإعدادات'); });")
      end

      dlg.add_action_callback("changePassword") do |_, new_pass|
        if update_password(new_pass)
          UI.messagebox("✅ تم تغيير كلمة المرور بنجاح.")
        else
          UI.messagebox("❌ فشل تغيير كلمة المرور.")
        end
      end

      dlg.add_action_callback("saveTaxCurrency") do |_, tax, currency|
        Sketchup.write_default("MHDESIGN_PRICING", "tax_rate", tax.to_s)
        Sketchup.write_default("MHDESIGN_PRICING", "currency_symbol", currency.to_s)
      end

      dlg.show
    end
  end
end
