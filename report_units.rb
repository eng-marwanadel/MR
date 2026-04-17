# encoding: UTF-8
# MRDESIGN - تقرير الوحدات (وحدة صامتة + قابل للتحرير + صور قابلة للتحريك والتحجيم مثل Word)

require 'sketchup'
require 'cgi'

module MRDESIGN
  module ReportUnits
    EXT_NAME = "MRDESIGN - إصدار تقرير للوحدات"

    CHASSIS = ["شاسيه ميلامين", "كونتر ابيض", "كونتر خشابي"]
    BACKS   = ["ظهر ابيض", "ظهر خشابي"]
    DOORS   = ["HPL", "POLYLACK", "UVLACK", "PVC", "MELAMIN"]

    def self.h(s) CGI.escapeHTML((s || "").to_s) end
    def self.to_cm(v) (v.to_f * 2.54).round(1) end

    def self.unit_name(inst)
      dict = inst.attribute_dictionary("dynamic_attributes", false)
      dict ? (dict["name"] || inst.definition.name) : inst.definition.name
    end

    def self.visible?(ent)
      return false if ent.hidden?
      return false if ent.respond_to?(:layer) && !ent.layer.visible?
      true
    end

    def self.entity_dims(ent)
      lenx = ent.get_attribute("dynamic_attributes", "lenx").to_f
      leny = ent.get_attribute("dynamic_attributes", "leny").to_f
      lenz = ent.get_attribute("dynamic_attributes", "lenz").to_f

      if lenx > 0 && leny > 0 && lenz > 0
        w = to_cm(lenx)
        d = to_cm(leny)
        h = to_cm(lenz)
      else
        bb = ent.bounds
        w = to_cm(bb.width)
        d = to_cm(bb.depth)
        h = to_cm(bb.height)
      end

      [w, d, h].map { |x| (x <= 2.0 ? nil : x&.round(1)) }
    end

    def self.entity_size(ent)
      dims = entity_dims(ent).compact.select { |x| x > 2.0 }
      return "" if dims.size < 2
      "#{dims[0]}×#{dims[1]}"
    end

    def self.unit_dims_str(ent)
      w, d, h = entity_dims(ent)
      return "" unless w && d && h
      "<div style='font-size:11px;line-height:1.4;text-align:center'>
        عرض: #{w} سم<br>
        ارتفاع: #{h} سم<br>
        عمق: #{d} سم
      </div>"
    end

    def self.collect_pieces(ent, arr = [])
      if (ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)) && visible?(ent)
        arr << ent
        ents = ent.is_a?(Sketchup::ComponentInstance) ? ent.definition.entities : ent.entities
        ents.each { |e| collect_pieces(e, arr) }
      end
      arr
    end

    def self.entity_material(ent)
      ent.material&.display_name
    end

    def self.compact(arr)
      counts = Hash.new(0)
      arr.each { |s| counts[s] += 1 }
      counts.map { |s,c| c>1 ? "(#{c}×) #{s}" : s }
    end

    def self.collect_unit(inst)
      name = unit_name(inst)
      dims_str = unit_dims_str(inst)

      data = { chassis: Hash.new { |h,k| h[k] = [] },
               back: Hash.new { |h,k| h[k] = [] },
               door: Hash.new { |h,k| h[k] = [] } }

      pieces = collect_pieces(inst)
      pieces.each do |p|
        mat = entity_material(p)
        next unless mat

        if CHASSIS.include?(mat)
          size = entity_size(p)
          data[:chassis][mat] << size unless size.empty?
        elsif BACKS.include?(mat)
          size = entity_size(p)
          data[:back][mat] << size unless size.empty?
        elsif DOORS.include?(mat)
          size = entity_size(p)
          data[:door][mat] << size unless size.empty?
        end
      end

      { name: name, dims: dims_str, data: data }
    end

    def self.render_cell(group_hash)
      return "" if group_hash.empty?
      group_hash.map do |mat, sizes|
        "<b>#{h(mat)}</b><br>" +
        compact(sizes).map { |s| "<div contenteditable='true'>#{h(s)}</div>" }.join("<br>")
      end.join("<hr>")
    end

    def self.build_html(units)
      rows = units.each_with_index.map do |u, i|
        "<tr>
           <td>#{i+1}</td>
          <td contenteditable='true' style='text-align:center'>
            <b>#{h(u[:name])}</b><br><small>#{u[:dims]}</small>
          </td>
          <td contenteditable='true'>#{render_cell(u[:data][:chassis])}</td>
          <td contenteditable='true'>#{render_cell(u[:data][:back])}</td>
          <td contenteditable='true'>#{render_cell(u[:data][:door])}</td>
          <td contenteditable='true'></td>
        </tr>"
      end.join

      <<-HTML
      <!DOCTYPE html>
      <html dir="rtl" lang="ar">
      <head>
        <meta charset="UTF-8">
        <title>#{EXT_NAME}</title>
        <style>
          body{font-family:Tahoma,Arial;background:#f6f8fb;padding:20px}
          table{width:100%;border-collapse:collapse;margin-bottom:20px;table-layout:fixed}
          th,td{border:1px solid #000;padding:6px;text-align:center;vertical-align:top;font-size:13px;overflow:hidden}
          th{background:#eee;}
          small{color:#555;font-size:11px}
          .actions{margin-bottom:10px;text-align:left}
          button{padding:6px 12px;margin-left:5px}
          td[contenteditable="true"] {background:#fffbe6;position:relative;}
          .header{text-align:center;margin-bottom:15px}
          .client{text-align:right;font-weight:bold;margin-bottom:5px;font-size:14px}
          .free-text{text-align:center;font-weight:bold;font-size:14px;margin-top:5px}
          .resizable {
            position: relative;
            display:inline-block;
            cursor:move;
            border:1px dashed #777;
            border-radius:3px;
            max-width:100%;
          }
          .resizable img {
            width:100%;
            height:auto;
            display:block;
            pointer-events:none;
            user-select:none;
          }
          .resizer {
            width:8px; height:8px;
            background:#00aaff;
            position:absolute;
            border-radius:50%;
            cursor:nwse-resize;
          }
          .resizer.br {bottom:-4px;right:-4px;}
          @media print {
            @page { size: A4 landscape; margin: 15mm; }
            .actions { display:none; }
            .resizer, .resizable { border:none; }
          }
        </style>
      </head>
      <body>
        <div class="actions">
          <button onclick="refresh()">تحديث</button>
          <button onclick="window.print()">طباعة / PDF</button>
          <button onclick="exportCSV()">تصدير CSV</button>
        </div>
        <div class="header">
          <div class="client" contenteditable="true">اسم العميل</div>
          <div class="free-text" contenteditable="true">اكتب هنا أي ملاحظات أو عنوان للتقرير</div>
        </div>
        <table>
          <thead>
            <tr>
              <th style="width:3%">م</th>
              <th style="width:20%">الموصيف</th>
              <th style="width:20%">الشاسيه</th>
              <th style="width:20%">الظهر</th>
              <th style="width:20%">الضلفة</th>
              <th style="width:17%">ملاحظات</th>
            </tr>
          </thead>
          <tbody>#{rows}</tbody>
        </table>

        <script>
        document.addEventListener('paste', e => {
          var items = (e.clipboardData || e.originalEvent.clipboardData).items;
          for (let i=0; i<items.length; i++){
            if(items[i].type.indexOf('image') !== -1){
              e.preventDefault();
              var blob = items[i].getAsFile();
              var reader = new FileReader();
              reader.onload = ev => {
                var wrap = document.createElement('div');
                wrap.className = 'resizable';
                wrap.style.width = '150px';
                var img = document.createElement('img');
                img.src = ev.target.result;
                var resizer = document.createElement('div');
                resizer.className = 'resizer br';
                wrap.appendChild(img);
                wrap.appendChild(resizer);
                var range = window.getSelection().getRangeAt(0);
                range.insertNode(wrap);
              };
              reader.readAsDataURL(blob);
            }
          }
        });

        // Move + Resize
        let selected = null, startX, startY, startW, startH;
        document.addEventListener('mousedown', e => {
          if(e.target.classList.contains('resizer')){
            selected = e.target.parentElement;
            startX = e.clientX;
            startY = e.clientY;
            startW = parseFloat(getComputedStyle(selected).width);
            startH = parseFloat(getComputedStyle(selected).height);
            e.preventDefault();
          } else if(e.target.classList.contains('resizable')){
            selected = e.target;
            selected.dataset.dragging = true;
            startX = e.clientX - selected.offsetLeft;
            startY = e.clientY - selected.offsetTop;
            e.preventDefault();
          }
        });

        document.addEventListener('mousemove', e => {
          if(selected){
            if(selected.dataset.dragging){
              selected.style.position='relative';
              selected.style.left = (e.clientX - startX)+'px';
              selected.style.top = (e.clientY - startY)+'px';
            } else {
              const ratio = startH/startW;
              let w = startW + (e.clientX - startX);
              selected.style.width = w+'px';
              selected.style.height = (w*ratio)+'px';
            }
          }
        });
        document.addEventListener('mouseup', ()=>{ if(selected){ delete selected.dataset.dragging; selected=null; }});
        </script>
      </body>
      </html>
      HTML
    end

    def self.show
      sel = Sketchup.active_model.selection
      if sel.empty?
        UI.messagebox("اختر وحدة أو أكثر")
        return
      end

      units = sel.grep(Sketchup::ComponentInstance).map { |i| collect_unit(i) }
      html = build_html(units)

      @dlg&.close
      @dlg = UI::HtmlDialog.new(dialog_title: EXT_NAME, width: 1400, height: 750, resizable: true)
      @dlg.set_html(html)
      @dlg.add_action_callback("refresh_report") { show }
      @dlg.show
    end

    # Silent Remote Module
    # يتم تشغيله من داخل المكتبة فقط بدون Menu أو Toolbar
  end
end
