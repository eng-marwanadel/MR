# encoding: UTF-8
require 'sketchup.rb'

module MHDESIGN

  # ==========================================================
  # âœ… LED Groove Tool (Hybrid V1 + V3 Special Cases)
  # - Default = original V1 logic for all units
  # - Special cases only = local V3 logic
  # - Activation entry: MHDESIGN::LEDGroove.activate_tool
  # ==========================================================

  module HandGroove90
    unless defined?(LOADED_ONCE)
      LOADED_ONCE = true

      IDENTITY = Geom::Transformation.new
      EPS = 0.2.mm

      DICT = "MHDESIGN_LED_GROOVE"
      KEYS = {
        margin: "end_margin_cm",
        inset:  "inset_cm",
        width:  "groove_w_cm",
        depth:  "depth_cm"
      }

      # âœ… Ø§Ù„Ø­Ø§Ù„Ø§Øª Ø§Ù„Ø®Ø§ØµØ© ÙÙ‚Ø·
      SPECIAL_PARENT_NAMES = [
        "Ø±ÙƒÙ†Ø© Ø¹Ù„ÙˆÙŠÙ‡ Ù…Ø´Ø·ÙˆØ±Ù‡",
        "Ø±ÙƒÙ†Ø© Ø¹Ù„ÙˆÙŠÙ‡ Ø­Ø±Ù Ø§Ù„"
      ]

      SPECIAL_PART_KEYWORDS = [
        "Ù‚Ø§Ø¹Ø¯Ø©",
        "Ù‚Ø§Ø¹Ø¯Ù‡"
      ]

      def self.activate_tool
        Sketchup.active_model.select_tool(Tool.new)
      end

      class Tool
        def initialize
          @settings = nil
          @asked = false

          @ip = Sketchup::InputPoint.new

          @face = nil
          @ents = nil
          @container = nil
          @path = nil

          @tr  = IDENTITY
          @inv = IDENTITY

          @state = :pick_start

          @start_w = nil
          @curr_w  = nil
          @start_l = nil

          # V1 world axes
          @origin_w = nil
          @axis_long_w  = nil
          @axis_short_w = nil
          @axis_mode = nil
          @n_w = nil

          # V3 local basis
          @origin_l = nil
          @axis_u_l = nil
          @axis_v_l = nil
          @axis_n_l = nil
          @axis_u_w = nil
          @axis_v_w = nil
          @drag_mode = nil

          # hybrid mode
          @use_local_special = false
        end

        # ---------- defaults ----------
        def load_defaults
          [
            Sketchup.read_default(DICT, KEYS[:margin], 0.0).to_f,
            Sketchup.read_default(DICT, KEYS[:inset],  4.0).to_f,
            Sketchup.read_default(DICT, KEYS[:width],  2.0).to_f,
            Sketchup.read_default(DICT, KEYS[:depth],  0.5).to_f
          ]
        end

        def save_defaults(vals)
          Sketchup.write_default(DICT, KEYS[:margin], vals[0].to_f)
          Sketchup.write_default(DICT, KEYS[:inset],  vals[1].to_f)
          Sketchup.write_default(DICT, KEYS[:width],  vals[2].to_f)
          Sketchup.write_default(DICT, KEYS[:depth],  vals[3].to_f)
        end

        # ---------- UI ----------
        def ask_settings
          prompts = [
            "Ù…Ù‚Ø§Ø³ Ø§Ù„Ø­ÙØ± (Ø§ØªØ±ÙƒÙ‡0Ù„Ø­ÙØ± ÙƒØ§Ù…Ù„ Ù„Ù„Ù‚Ø·Ø¹Ù‡)(Ø³Ù…)",
            "Ø¨Ø¯Ø§ÙŠØ© Ø§Ù„Ø­ÙØ± (Ø³Ù…)",
            "Ø¹Ø±Ø¶ Ø§Ù„Ø­ÙØ± (Ø³Ù…)",
            "Ø³Ù‚ÙˆØ· Ø§Ù„Ø­ÙØ± (Ø³Ù…)"
          ]
          defaults = @settings || load_defaults
          input = UI.inputbox(prompts, defaults, "MHDESIGN | LED Groove (Hybrid)")
          return false unless input
          @settings = input.map(&:to_f)
          save_defaults(@settings)
          true
        end

        def activate
          unless @asked
            ok = ask_settings
            @asked = true
            unless ok
              Sketchup.active_model.select_tool(nil)
              return
            end
          end
          Sketchup.set_status_text("Click A â†’ Drag â†’ Click B (Cut) | R ØªØ¹Ø¯ÙŠÙ„ | Esc Ø®Ø±ÙˆØ¬", SB_PROMPT)
        end

        def onKeyDown(key, repeat, flags, view)
          case key
          when 27
            Sketchup.active_model.select_tool(nil)
          when 'R'.ord
            ask_settings
            view.invalidate
          end
        end

        # ==========================================================
        # helpers
        # ==========================================================
        def normalize_ar(str)
          s = str.to_s.dup
          s = s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          s.gsub!(/\s+/, "")
          s.tr!("Ø£Ø¥Ø¢", "Ø§Ø§Ø§")
          s.tr!("Ø©", "Ù‡")
          s.tr!("Ù‰", "ÙŠ")
          s.downcase
        rescue
          str.to_s.downcase.gsub(/\s+/, "")
        end

        def text_contains_any?(text, arr)
          nt = normalize_ar(text)
          arr.any? { |x| nt.include?(normalize_ar(x)) }
        end

        def dynamic_name_of(entity)
          return "" unless entity

          val =
            entity.get_attribute("dynamic_attributes", "name") ||
            entity.get_attribute("dynamic_attributes", "_name_label") ||
            entity.get_attribute("dynamic_attributes", "Name") ||
            entity.name

          val.to_s
        rescue
          ""
        end

        def definition_name_of(entity)
          return "" unless entity

          if entity.is_a?(Sketchup::ComponentInstance)
            entity.definition ? entity.definition.name.to_s : ""
          elsif entity.is_a?(Sketchup::Group)
            entity.definition ? entity.definition.name.to_s : entity.name.to_s
          else
            ""
          end
        rescue
          ""
        end

        def full_path_transformation_to_parent(path, container)
          tr = IDENTITY
          arr = path.to_a

          arr.each do |e|
            break if e == container
            if e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
              tr = tr * e.transformation
            end
          end

          if container.is_a?(Sketchup::ComponentInstance) || container.is_a?(Sketchup::Group)
            tr = tr * container.transformation
          end

          tr
        rescue
          IDENTITY
        end

        def parent_container_of_face_in_path(path, face)
          arr = path.to_a
          idx = arr.index(face)
          return nil unless idx

          (idx - 1).downto(0) do |i|
            e = arr[i]
            return e if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          end

          nil
        end

        def local_face_plane
          p0 = @face.vertices.first.position
          n  = @face.normal
          [p0, n]
        end

        def project_point_to_face_plane(pt)
          pt.project_to_plane(local_face_plane)
        rescue
          pt
        end

        def points_too_close?(pts)
          return true if pts.nil? || pts.length < 4
          pts.each_with_index do |a, i|
            ((i + 1)...pts.length).each do |j|
              b = pts[j]
              return true if a.distance(b) < 0.1.mm
            end
          end
          false
        end

        def special_case_selected?
          return false unless @container && @path

          part_def_name = definition_name_of(@container)
          return false unless text_contains_any?(part_def_name, SPECIAL_PART_KEYWORDS)

          arr = @path.to_a
          parent_match = arr.any? do |e|
            next false unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
            unit_name = dynamic_name_of(e)
            text_contains_any?(unit_name, SPECIAL_PARENT_NAMES)
          end

          parent_match
        rescue
          false
        end

        # ==========================================================
        # picking
        # ==========================================================
        def pick_face_using_inputpoint(view, x, y)
          @face = nil
          @ents = nil
          @container = nil
          @path = nil
          @tr = IDENTITY
          @inv = IDENTITY

          @ip.pick(view, x, y)
          ip_face = @ip.face
          return unless ip_face.is_a?(Sketchup::Face)

          ph = view.pick_helper
          ph.do_pick(x, y)

          chosen_path = nil
          chosen_container = nil

          (0...ph.count).each do |i|
            pth = ph.path_at(i)
            next unless pth && pth.any?

            arr = pth.to_a
            face_index = arr.index(ip_face)
            next unless face_index

            parent = nil
            (face_index - 1).downto(0) do |j|
              e = arr[j]
              if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
                parent = e
                break
              end
            end

            chosen_path = pth
            chosen_container = parent
            break
          end

          return unless chosen_path

          if chosen_container
            ents = chosen_container.is_a?(Sketchup::Group) ? chosen_container.entities : chosen_container.definition.entities
            tr = full_path_transformation_to_parent(chosen_path, chosen_container)
          else
            ents = Sketchup.active_model.active_entities
            tr = IDENTITY
          end

          return unless ents

          @face = ip_face
          @ents = ents
          @container = chosen_container
          @path = chosen_path
          @tr = tr
          @inv = tr.inverse
          @use_local_special = special_case_selected?
        rescue => e
          puts "pick_face ERROR: #{e.class} - #{e.message}"
        end

        # ==========================================================
        # V1 geometry helpers (WORLD)
        # ==========================================================
        def compute_axes_world_from_face
          verts_w = @face.outer_loop.vertices.map { |v| v.position.transform(@tr) }
          @origin_w = verts_w.first

          edges = @face.outer_loop.edges
          long_e  = edges.max_by(&:length)
          short_e = edges.min_by(&:length)

          a = long_e.start.position.transform(@tr)
          b = long_e.end.position.transform(@tr)
          v1 = b - a
          @axis_long_w = Geom::Vector3d.new(v1.x, v1.y, v1.z)
          @axis_long_w.normalize!

          c = short_e.start.position.transform(@tr)
          d = short_e.end.position.transform(@tr)
          v2 = d - c
          @axis_short_w = Geom::Vector3d.new(v2.x, v2.y, v2.z)
          @axis_short_w.normalize!

          n_local = @face.normal
          n_w_tmp = n_local.transform(@tr)
          @n_w = Geom::Vector3d.new(n_w_tmp.x, n_w_tmp.y, n_w_tmp.z)
          @n_w.normalize!
        end

        def coord_world(pt_w, axis_w)
          d = pt_w - @origin_w
          Geom::Vector3d.new(d.x, d.y, d.z).dot(axis_w)
        end

        # ==========================================================
        # V3 local basis
        # ==========================================================
        def setup_local_basis
          verts = @face.outer_loop.vertices.map(&:position)
          raise "No face vertices found" if verts.empty?

          edges = @face.outer_loop.edges
          long_e = edges.max_by(&:length)
          raise "No valid face edges found" unless long_e

          p1 = long_e.start.position
          p2 = long_e.end.position

          axis_u = p2 - p1
          raise "Invalid long edge" if axis_u.length < 0.001.mm
          axis_u = Geom::Vector3d.new(axis_u.x, axis_u.y, axis_u.z)
          axis_u.normalize!

          axis_n = @face.normal
          axis_n = Geom::Vector3d.new(axis_n.x, axis_n.y, axis_n.z)
          axis_n.normalize!

          axis_v = axis_n * axis_u
          raise "Invalid perpendicular axis" if axis_v.length < 0.001.mm
          axis_v.normalize!

          @origin_l = p1
          @axis_u_l = axis_u
          @axis_v_l = axis_v
          @axis_n_l = axis_n

          u_w_tmp = @axis_u_l.transform(@tr)
          @axis_u_w = Geom::Vector3d.new(u_w_tmp.x, u_w_tmp.y, u_w_tmp.z)
          @axis_u_w.normalize!

          v_w_tmp = @axis_v_l.transform(@tr)
          @axis_v_w = Geom::Vector3d.new(v_w_tmp.x, v_w_tmp.y, v_w_tmp.z)
          @axis_v_w.normalize!
        end

        def coord_local(pt_l, axis_l)
          d = pt_l - @origin_l
          Geom::Vector3d.new(d.x, d.y, d.z).dot(axis_l)
        end

        def point_from_uv(u, v)
          Geom::Point3d.new(
            @origin_l.x + @axis_u_l.x * u + @axis_v_l.x * v,
            @origin_l.y + @axis_u_l.y * u + @axis_v_l.y * v,
            @origin_l.z + @axis_u_l.z * u + @axis_v_l.z * v
          )
        end

        def face_bounds_uv
          verts = @face.outer_loop.vertices.map(&:position)
          us = verts.map { |pt| coord_local(pt, @axis_u_l) }
          vs = verts.map { |pt| coord_local(pt, @axis_v_l) }
          [us.min, us.max, vs.min, vs.max]
        end

        def point_inside_face_local?(pt_l)
          klass = @face.classify_point(pt_l)
          return true if klass == Sketchup::Face::PointInside
          return true if klass == Sketchup::Face::PointOnEdge
          return true if klass == Sketchup::Face::PointOnVertex
          false
        rescue
          false
        end

        def safe_inside_face?(pts)
          pts.all? { |p| point_inside_face_local?(p) }
        end

        def safe_add_face(ents, pts)
          face = nil

          begin
            face = ents.add_face(pts)
          rescue
            face = nil
          end
          return face if face && face.valid?

          begin
            face = ents.add_face(pts.reverse)
          rescue
            face = nil
          end
          return face if face && face.valid?

          nil
        end

        # ==========================================================
        # mouse
        # ==========================================================
        def onMouseMove(flags, x, y, view)
          @ip.pick(view, x, y)
          return unless @face

          pt_w = @ip.position
          return unless pt_w.is_a?(Geom::Point3d)
          @curr_w = pt_w

          if @state == :drag
            if @use_local_special
              if @start_w && @axis_u_w && @axis_v_w
                drag = @curr_w - @start_w
                return if drag.length < 1.mm
                @drag_mode = (drag.dot(@axis_u_w).abs > drag.dot(@axis_v_w).abs) ? :u : :v
              end
            else
              if @start_w && @axis_long_w && @axis_short_w
                v_drag = @curr_w - @start_w
                return if v_drag.length < 1.mm
                @axis_mode = (v_drag.dot(@axis_long_w).abs > v_drag.dot(@axis_short_w).abs) ? :long : :short
              end
            end
          end

          view.invalidate
        rescue => e
          puts "onMouseMove ERROR: #{e.class} - #{e.message}"
        end

        def onLButtonDown(flags, x, y, view)
          if @state == :pick_start
            pick_face_using_inputpoint(view, x, y)
            return unless @face && @ents

            pt_w = @ip.position
            return unless pt_w.is_a?(Geom::Point3d)
            @start_w = pt_w

            if @use_local_special
              setup_local_basis
              @start_l = pt_w.transform(@inv)
              @drag_mode = nil
            else
              compute_axes_world_from_face
              @axis_mode = nil
            end

            @state = :drag
            return
          end

          if @state == :drag
            if @use_local_special
              return unless @drag_mode
              perform_cut_local
            else
              return unless @axis_mode
              perform_cut_world
            end
            reset_for_next_cut
            view.invalidate
          end
        rescue => e
          UI.messagebox("Ø®Ø·Ø£:\n#{e.class}\n#{e.message}")
          puts "onLButtonDown ERROR: #{e.class} - #{e.message}"
        end

        def reset_for_next_cut
          @face = nil
          @ents = nil
          @container = nil
          @path = nil
          @tr  = IDENTITY
          @inv = IDENTITY

          @state = :pick_start

          @start_w = nil
          @curr_w  = nil
          @start_l = nil

          @origin_w = nil
          @axis_long_w = nil
          @axis_short_w = nil
          @axis_mode = nil
          @n_w = nil

          @origin_l = nil
          @axis_u_l = nil
          @axis_v_l = nil
          @axis_n_l = nil
          @axis_u_w = nil
          @axis_v_w = nil
          @drag_mode = nil

          @use_local_special = false
        end

        # ==========================================================
        # draw
        # ==========================================================
        def draw(view)
          return unless @state == :drag && @start_w

          axis = nil
          if @use_local_special
            return unless @drag_mode
            axis = (@drag_mode == :u) ? @axis_u_w : @axis_v_w
          else
            return unless @axis_mode
            axis = (@axis_mode == :long) ? @axis_long_w : @axis_short_w
          end

          return unless axis

          a = @start_w
          b = Geom::Point3d.new(
            @start_w.x + axis.x * 140.mm,
            @start_w.y + axis.y * 140.mm,
            @start_w.z + axis.z * 140.mm
          )

          view.line_width = 3
          view.drawing_color = "black"
          view.draw(GL_LINES, [a, b])
        rescue => e
          puts "draw ERROR: #{e.class} - #{e.message}"
        end

        # ==========================================================
        # CUT 1 = original V1 logic
        # ==========================================================
        def perform_cut_world
          return unless @settings && @face && @ents && @start_w

          end_margin_w = @settings[0].to_f.cm
          inset_w      = @settings[1].to_f.cm
          groove_w_w   = @settings[2].to_f.cm
          depth_w      = @settings[3].to_f.cm

          verts_w = @face.outer_loop.vertices.map { |v| v.position.transform(@tr) }

          axis = (@axis_mode == :long) ? @axis_long_w : @axis_short_w
          perp = (@axis_mode == :long) ? @axis_short_w : @axis_long_w

          a_vals = verts_w.map { |pt| coord_world(pt, axis) }
          a_min, a_max = a_vals.minmax
          full_len = (a_max - a_min).abs
          end_margin_w = 0.0 if full_len - (2.0 * end_margin_w) < 2.mm
          a_min += end_margin_w
          a_max -= end_margin_w

          b_vals = verts_w.map { |pt| coord_world(pt, perp) }
          b_min, b_max = b_vals.minmax
          full_w = (b_max - b_min).abs
          groove_w_w = [groove_w_w, full_w - 2.mm].min
          groove_w_w = 1.mm if groove_w_w < 1.mm

          pick_b = coord_world(@start_w, perp)
          dist_to_min = (pick_b - b_min).abs
          dist_to_max = (b_max - pick_b).abs
          boundary = (dist_to_min <= dist_to_max) ? b_min : b_max

          cx = cy = cz = 0.0
          verts_w.each { |p| cx += p.x; cy += p.y; cz += p.z }
          center_w = Geom::Point3d.new(cx / verts_w.length, cy / verts_w.length, cz / verts_w.length)
          center_b = coord_world(center_w, perp)
          inward_sign = (center_b >= boundary) ? +1.0 : -1.0

          available =
            if inward_sign > 0
              (b_max - boundary) - groove_w_w - EPS
            else
              (boundary - b_min) - groove_w_w - EPS
            end
          available = 0.0 if available < 0.0

          inset = inset_w
          inset = 0.0 if inset < 0.0
          inset = available if inset > available

          b1 = boundary + inward_sign * inset
          b2 = b1 + inward_sign * groove_w_w

          pw = lambda do |t, s|
            Geom::Point3d.new(
              @origin_w.x + axis.x * t + perp.x * s,
              @origin_w.y + axis.y * t + perp.y * s,
              @origin_w.z + axis.z * t + perp.z * s
            )
          end

          p1_w = pw.call(a_min, b1)
          p2_w = pw.call(a_max, b1)
          p3_w = pw.call(a_max, b2)
          p4_w = pw.call(a_min, b2)

          p1 = p1_w.transform(@inv)
          p2 = p2_w.transform(@inv)
          p3 = p3_w.transform(@inv)
          p4 = p4_w.transform(@inv)

          n_local = @face.normal
          n_local_u = Geom::Vector3d.new(n_local.x, n_local.y, n_local.z)
          n_local_u.normalize!
          n_w_vec = n_local_u.transform(@tr)
          s_n = n_w_vec.length
          s_n = 1.0 if s_n < 1e-9
          depth_local = depth_w / s_n

          model = Sketchup.active_model
          model.start_operation("MHDESIGN - LED Groove (V1 Default)", true)

          groove_face = @ents.add_face(p1, p2, p3, p4)
          if groove_face && groove_face.valid?
            begin
              groove_face.pushpull(-depth_local)
            rescue
              groove_face.reverse!
              groove_face.pushpull(-depth_local)
            end
          end

          model.commit_operation
        rescue => e
          Sketchup.active_model.abort_operation rescue nil
          UI.messagebox("Ø®Ø·Ø£ Ø£Ø«Ù†Ø§Ø¡ Ø§Ù„Ù‚Ø·Ø¹:\n#{e.class}\n#{e.message}")
          puts "perform_cut_world ERROR: #{e.class} - #{e.message}"
        end

        # ==========================================================
        # CUT 2 = V3 logic for special units only
        # ==========================================================
        def perform_cut_local
          return unless @settings && @face && @ents && @start_l

          end_margin = @settings[0].to_f.cm
          inset      = @settings[1].to_f.cm
          groove_w   = @settings[2].to_f.cm
          depth      = @settings[3].to_f.cm

          u_min, u_max, v_min, v_max = face_bounds_uv

          start_u = coord_local(@start_l, @axis_u_l)
          start_v = coord_local(@start_l, @axis_v_l)

          if @drag_mode == :u
            run_min = u_min
            run_max = u_max
            side_min = v_min
            side_max = v_max
            pick_side = start_v
          else
            run_min = v_min
            run_max = v_max
            side_min = u_min
            side_max = u_max
            pick_side = start_u
          end

          full_len = (run_max - run_min).abs
          end_margin = 0.0 if full_len - (2.0 * end_margin) < 2.mm
          a1 = run_min + end_margin
          a2 = run_max - end_margin

          full_width = (side_max - side_min).abs
          groove_w = [groove_w, full_width - 2.mm].min
          groove_w = 1.mm if groove_w < 1.mm

          dist_to_min = (pick_side - side_min).abs
          dist_to_max = (side_max - pick_side).abs
          boundary = (dist_to_min <= dist_to_max) ? side_min : side_max

          face_center = @face.bounds.center
          center_u = coord_local(face_center, @axis_u_l)
          center_v = coord_local(face_center, @axis_v_l)
          center_side = (@drag_mode == :u) ? center_v : center_u

          inward_sign = (center_side >= boundary) ? +1.0 : -1.0

          available =
            if inward_sign > 0
              (side_max - boundary) - groove_w - EPS
            else
              (boundary - side_min) - groove_w - EPS
            end
          available = 0.0 if available < 0.0

          inset = 0.0 if inset < 0.0
          inset = available if inset > available

          b1 = boundary + inward_sign * inset
          b2 = b1 + inward_sign * groove_w

          if @drag_mode == :u
            p1 = point_from_uv(a1, b1)
            p2 = point_from_uv(a2, b1)
            p3 = point_from_uv(a2, b2)
            p4 = point_from_uv(a1, b2)
          else
            p1 = point_from_uv(b1, a1)
            p2 = point_from_uv(b2, a1)
            p3 = point_from_uv(b2, a2)
            p4 = point_from_uv(b1, a2)
          end

          pts = [p1, p2, p3, p4]

          if points_too_close?(pts)
            UI.messagebox("ØªØ¹Ø°Ø± Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„Ø­ÙØ±Ø©: Ø£Ø¨Ø¹Ø§Ø¯ Ø§Ù„Ø­ÙØ± ØµØºÙŠØ±Ø© Ø¬Ø¯Ù‹Ø§ Ø£Ùˆ Ø§Ù„Ù†Ù‚Ø§Ø· Ù…ØªØ¯Ø§Ø®Ù„Ø©.")
            return
          end

          unless safe_inside_face?(pts)
            UI.messagebox("ØªØ¹Ø°Ø± Ø¥Ù†Ø´Ø§Ø¡ Ø§Ù„Ø­ÙØ±Ø©: Ø§Ù„Ø­ÙØ±Ø© Ø®Ø±Ø¬Øª Ø®Ø§Ø±Ø¬ Ø­Ø¯ÙˆØ¯ Ø³Ø·Ø­ Ø§Ù„Ù‚Ø·Ø¹Ø©. Ø¬Ø±Ù‘Ø¨ ØªÙ‚Ù„ÙŠÙ„ Ø§Ù„Ø¹Ø±Ø¶ Ø£Ùˆ Ø§Ù„Ø¨Ø¯Ø§ÙŠØ©.")
            return
          end

          model = Sketchup.active_model
          model.start_operation("MHDESIGN - LED Groove (V3 Special)", true)

          groove_face = safe_add_face(@ents, pts)

          unless groove_face && groove_face.valid?
            raise ArgumentError, "Failed to create groove face"
          end

          begin
            groove_face.pushpull(-depth)
          rescue
            groove_face.reverse!
            groove_face.pushpull(-depth)
          end

          model.commit_operation
        rescue => e
          Sketchup.active_model.abort_operation rescue nil
          UI.messagebox("Ø®Ø·Ø£ Ø£Ø«Ù†Ø§Ø¡ Ø§Ù„Ù‚Ø·Ø¹:\n#{e.class}\n#{e.message}")
          puts "perform_cut_local ERROR: #{e.class} - #{e.message}"
        end
      end

    end
  end

end
