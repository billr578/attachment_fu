require 'RMagick'
module Technoweenie # :nodoc:
  module AttachmentFu # :nodoc:
    module Processors
      module RmagickProcessor
        def self.included(base)
          base.send :extend, ClassMethods
          base.alias_method_chain :process_attachment, :processing
        end

        module ClassMethods
          # Yields a block containing an RMagick Image for the given binary data.
          def with_image(file, &block)
            begin
              binary_data = file.is_a?(Magick::Image) ? file : Magick::Image.read(file).first unless !Object.const_defined?(:Magick)
              binary_data && binary_data.auto_orient!
            rescue
              # Log the failure to load the image.  This should match ::Magick::ImageMagickError
              # but that would cause acts_as_attachment to require rmagick.
              logger.debug("Exception working with image: #{$!}")
              binary_data = nil
            end
            block.call binary_data if block && binary_data
          ensure
            !binary_data.nil?
          end
        end

      protected
        def process_attachment_with_processing
          return unless process_attachment_without_processing
          with_image do |img|
            resize_image_or_thumbnail! img
            self.width  = img.columns if respond_to?(:width)
            self.height = img.rows    if respond_to?(:height)
            callback_with_args :after_resize, img
          end if image?
        end

        # Override image resizing method so we can support the crop option
        # Thanks: http://stuff-things.net/2008/02/21/quick-and-dirty-cropping-images-with-attachment_fu/
        def resize_image(img, size)
          img.delete_profile('*')

          # resize_image take size in a number of formats, we just want
          # Strings in the form of "crop: WxH"
          if (size.is_a?(String) && size =~ /^crop: (\d*)x(\d*)/i) ||
              (size.is_a?(Array) && size.first.is_a?(String) &&
                size.first =~ /^crop: (\d*)x(\d*)/i)
            img.crop_resized!($1.to_i, $2.to_i)
            # We need to save the resized image in the same way the
            # orignal does.
            quality = img.format.to_s[/JPEG/] && get_jpeg_quality
            out_file = write_to_temp_file(img.to_blob { self.quality = quality if quality })
            self.temp_paths.unshift out_file
          else
            old_resize_image(img, size) # Otherwise let attachment_fu handle it
          end
        end

        # Performs the actual resizing operation for a thumbnail
        def old_resize_image(img, size)
          size = size.first if size.is_a?(Array) && size.length == 1 && !size.first.is_a?(Fixnum)
          if size.is_a?(Fixnum) || (size.is_a?(Array) && size.first.is_a?(Fixnum))
            size = [size, size] if size.is_a?(Fixnum)
            img.thumbnail!(*size)
          elsif size.is_a?(String) && size =~ /^c.*$/ # Image cropping - example geometry string: c75x75
            dimensions = size[1..size.size].split("x")
            img.crop_resized!(dimensions[0].to_i, dimensions[1].to_i)
          else
            img.change_geometry(size.to_s) { |cols, rows, image| image.resize!(cols<1 ? 1 : cols, rows<1 ? 1 : rows) }
          end
          self.width  = img.columns if respond_to?(:width)
          self.height = img.rows    if respond_to?(:height)
          img.strip! unless attachment_options[:keep_profile]
          quality = img.format.to_s[/JPEG/] && get_jpeg_quality
          out_file = write_to_temp_file(img.to_blob { self.quality = quality if quality })
          temp_paths.unshift out_file
          self.size = File.size(self.temp_path)
        end
      end
    end
  end
end