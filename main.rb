require 'ostruct'
require 'open3'

def sources
  # ノイズの粒度によるバリエーション
  sources = Dir.glob('./original/*').map do |f|
    ext = File.extname f
    filename = File.basename f, ext

    tiff = File.join('./tiff', "#{filename}.tif")
    `convert -compress none -alpha remove #{f} #{tiff}`

    values = {}
    values[:type] = 'entropy'
    values[:path] = tiff
    values[:filename] = filename
    values[:filesize] = File.size(tiff)

    if filename =~ /(\d+)x(\d+)/
      values[:block_size] = $1.to_i
      values[:blocks] = $2.to_i
      values[:block_count] = $2.to_i * $2.to_i
    end

    values
  end

  # ノイズ領域の広さによるバリエーション
  width = 256
  sources += 10.step(100, 10).map do |share|
    w = Math.sqrt(width * width * share / 100).to_i
    filename = "#{share}%noize"
    ext = ".tif"
    tiff = File.join('./tiff', "#{share}%noize.tif")

    `convert -gravity center -crop #{w}x#{w}+0x0 ./tiff/1x256.tif ./tmp/crop.tif`
    `composite -gravity center -compose over ./tmp/crop.tif ./tiff/256x1.tif #{tiff}`

    values = {}
    values[:type] = 'share'
    values[:path] = tiff
    values[:filename] = filename
    values[:ext] = ext
    values[:filesize] = File.size(tiff)
    values[:share] = share

    values
  end

  # ユニークな色数の取得
  sources.each do |source|
    info = `/usr/local/bin/identify -verbose -unique #{source[:path]}`
    if info =~ /Colors:\s(\d+)/
      source[:colors] = $1.to_i
    end
  end

  sources
end

def converts
  converts = []

  # Jpeg変換のバリエーション
  converts += 10.step(100, 10).map do |quality|
    { format: 'jpg', ext: '.jpg', quality: quality, suffix: "-q#{quality}" }
  end

  # PNG変換のバリエーション
  converts += [8, 24].map do |bits|
    { format: 'png', ext: '.png', bits: bits, suffix: "-b#{bits}" }
  end
end

def compares
  compares = [
    { metric: 'SSIM', key: 'ssim' }
  ]
end

def run
  results = []
  sources.each do |source|
    converts.each do |convert|
      result = {src_file: source[:filename], src_size: source[:filesize], block: source[:block_size], blocks: source[:blocks], share: source[:share], colors: source[:colors]}
      result[:type] = source[:type]

      result.merge! format: convert[:format], quality: convert[:quality], bits: convert[:bits]
      result[:key] = result[:blocks] ? 'b' + result[:block].to_s.rjust(3, '0') + convert[:suffix] : 'n' + result[:share].to_s.rjust(3, '0') + convert[:suffix]

      result[:path] = source[:filename] + convert[:suffix] + convert[:ext]
      dest = File.join('./results', result[:path])

      # フォーマットとそのパラメータにより変換
      if convert[:format] == 'jpg'
        `convert -quality #{convert[:quality]} #{source[:path]} #{dest}`
      elsif convert[:format] == 'png'
        `convert #{source[:path]} png#{convert[:bits]}:#{dest}`
      end

      result[:dest_size] = File.size(dest)

      # オリジナルとの差分比較
      compares.each do |compare|
        _, value = Open3.capture3("compare -metric #{compare[:metric]} #{source[:path]} #{dest} NULL:")
        if value =~ /([\d\.]+)/
          result[compare[:key].to_sym] = $1.to_f
        end
      end

      results << result
    end
  end

  results
end

# 結果の整形と出力
headers = %i(key path type block blocks share colors format quality bits src_size dest_size)
headers += compares.map{|c| c[:key].to_sym}

results = run

puts headers.join("\t")
results.each do |result|
  puts headers.map{|h| result[h]}.join("\t")
end