###########
# Website #
###########

resource "aws_s3_bucket_object" "site_asset_manifest" {
  bucket       = var.site_domain
  key          = "manifest.json"
  source       = "../public/manifest.json"
  content_type = "application/json"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = "${filemd5("../public/manifest.json")}"
}

resource "aws_s3_bucket_object" "site_asset_index" {
  bucket       = var.site_domain
  key          = "index.html"
  source       = "../public/index.html"
  content_type = "text/html"


  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = "${filemd5("../public/index.html")}"
}

resource "aws_s3_bucket_object" "site_asset_favicon" {
  bucket = var.site_domain
  key    = "favicon.ico"
  source = "../public/favicon.ico"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = "${filemd5("../public/favicon.ico")}"
}

resource "aws_s3_bucket" "website" {
  bucket = var.site_domain

  website {
    index_document = "index.html"
    error_document = "index.html"
  }

  tags = {
    Project = var.app_name
    Stage   = var.stage
  }
}

locals {
  s3_origin_id = "S3-${var.site_domain}"
}

resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name = aws_s3_bucket.website.website_endpoint
    origin_id   = local.s3_origin_id

    // The redirect origin must be http even if it's on S3 for redirects to work properly
    // so the website_endpoint is used and http-only as S3 doesn't support https for this
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  aliases = [var.site_domain]

  enabled         = true
  is_ipv6_enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      cookies {
        forward = "none"
      }

      query_string = false
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    max_ttl                = 31536000
    default_ttl            = 86400
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.website.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

###############
# DNS Routing #
###############

resource "aws_route53_record" "website" {
  zone_id = data.aws_route53_zone.website.zone_id
  name    = data.aws_route53_zone.website.name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = true
  }
}

#################
# Access Policy #
#################

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.website.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Resource": "${aws_s3_bucket.website.arn}/*"
    }
  ]
}
POLICY

}

