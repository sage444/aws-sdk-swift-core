//
//  V4.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/03/13.
//
//

import Foundation

extension Signers {
    public final class V4 {

        public var credential: CredentialProvider?

        public let region: Region

        public let service: String

        let identifier = "aws4_request"

        let algorithm = "AWS4-HMAC-SHA256"

        var unsignableHeaders: [String] {
            return [
                "authorization",
                "content-type",
                "content-length",
                "user-agent",
                "presigned-expires",
                "expect",
                "x-amzn-trace-id"
            ]
        }

        func hexEncodedBodyHash(_ data: Data) -> String {
            if data.isEmpty && service == "s3" {
                return "UNSIGNED-PAYLOAD"
            }
            return sha256(data).hexdigest()
        }

        public init(credential: CredentialProvider?, region: Region, service: String) {
            self.credential = credential
            self.region = region
            self.service = service
        }

        public func signedURL(url: URL, date: Date = Date(), expires: Int = 86400) -> URL {
//            let datetime = V4.timestamp(date)
//            var headers = ["Host": url.hostWithPort!]
//
//            let bodyDigest = hexEncodedBodyHash(Data())
//            let credentialForSignature = getCredential()
            
            var queries: [URLQueryItem] = []
//            var queries = [
//                URLQueryItem(name: "X-Amz-Algorithm", value: algorithm),
//                URLQueryItem(name: "X-Amz-Date", value: datetime),
//                URLQueryItem(name: "X-Amz-Expires", value: "\(expires)"),
//                URLQueryItem(name: "X-Amz-SignedHeaders", value: "host;X-Amz-Security-Token"),
//            ]
//            if let credentialForSignature = credentialForSignature {
//                queries.append(
//                    URLQueryItem(name: "X-Amz-Credential", value: credentialForSignatureWithScope(credentialForSignature, datetime).replacingOccurrences(of: "/", with: "%2F"))
//                )
//                if let token = credentialForSignature.sessionToken {
//                    headers["X-Amz-Security-Token"] = token
//                }
//            }
            
            url.query?.components(separatedBy: "&").forEach {
                var q = $0.components(separatedBy: "=")
                if q.count == 2 {
                    queries.append(URLQueryItem(name: q[0], value: q[1].addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)))
                } else {
                    queries.append(URLQueryItem(name: q[0], value: nil))
                }
            }
            
            queries = queries.sorted { a, b in a.name < b.name }
            
            let url = URL(string: url.absoluteString.components(separatedBy: "?")[0]+"?"+queries.asStringForURL)!
//            if let credentialForSignature = credentialForSignature {
//                let sig = signature(
//                    url: url,
//                    headers: headers,
//                    datetime: datetime,
//                    method: "GET",
//                    bodyDigest: bodyDigest,
//                    credentialForSignature: credentialForSignature
//                )
//
//                return URL(string: url.absoluteString+"&X-Amz-Signature="+sig)!
//            } else {
                return url
//            }
        }

        public func signedHeaders(url: URL, headers: [String: String], method: String, date: Date = Date(), bodyData: Data) -> [String: String] {
            let datetime = V4.timestamp(date)
            let bodyDigest = hexEncodedBodyHash(bodyData)
            
            
            var headersForSign = [
                "x-amz-content-sha256": hexEncodedBodyHash(bodyData),
                "x-amz-date": datetime,
                "Host": url.hostWithPort!,
            ]
            
            for header in headers {
                if unsignableHeaders.contains(header.key.lowercased()) { continue }
                headersForSign[header.key] = header.value
            }
            
            if let credentialForSignature = getCredential() {
                headersForSign["Authorization"] = authorization(
                    url: url,
                    headers: headersForSign,
                    datetime: datetime,
                    method: method,
                    bodyDigest: bodyDigest,
                    credentialForSignature: credentialForSignature
                )
                
                if let token = credentialForSignature.sessionToken {
                    headersForSign["x-amz-security-token"] = token
                }
            }
            return headersForSign
        }

        static func timestamp(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(abbreviation: "UTC")
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.string(from: date)
        }

        func getCredential() -> CredentialProvider? {
            if let credential = credential, credential.isEmpty() || credential.nearExpiration() {
                return nil

            }
            return credential
        }

        func authorization(url: URL, headers: [String: String], datetime: String, method: String, bodyDigest: String, credentialForSignature: CredentialProvider) -> String {
            let cred = credentialForSignatureWithScope(credentialForSignature, datetime)
            var _headers = headers
            if let token = credentialForSignature.sessionToken {
                _headers["x-amz-security-token"] = token
            }
            let shead = signedHeaders(_headers)

            let sig = signature(
                url: url,
                headers: _headers,
                datetime: datetime,
                method: method,
                bodyDigest: bodyDigest,
                credentialForSignature: credentialForSignature
            )

            return [
                "AWS4-HMAC-SHA256 Credential=\(cred)",
                "SignedHeaders=\(shead)",
                "Signature=\(sig)",
            ].joined(separator: ", ")
        }

        func credentialForSignatureWithScope(_ credentialForSignature: CredentialProvider, _ datetime: String) -> String {
            return "\(credentialForSignature.accessKeyId)/\(credentialScope(datetime))"
        }

        func signedHeaders(_ headers: [String:String]) -> String {
            var list = Array(headers.keys).map { $0.lowercased() }.sorted()
            if let index = list.index(of: "authorization") {
                list.remove(at: index)
            }
            return list.joined(separator: ";")
        }

        func canonicalHeaders(_ headers: [String: String]) -> String {
            var list = [String]()
            let keys = Array(headers.keys).sorted()

            for key in keys {
                if key.caseInsensitiveCompare("authorization") != ComparisonResult.orderedSame {
                    list.append("\(key.lowercased()):\(headers[key]!)")
                }
            }
            return list.joined(separator: "\n")
        }

        func signature(url: URL, headers: [String: String], datetime: String, method: String, bodyDigest: String, credentialForSignature: CredentialProvider) -> String {
            let secretAccessKey = "AWS4\(credentialForSignature.secretAccessKey)"

            let secretBytes = Array(secretAccessKey.utf8)
            let date = hmac(
                string: String(datetime.prefix(upTo: datetime.index(datetime.startIndex, offsetBy: 8))),
                key: secretBytes
            )
            let region = hmac(string: self.region.rawValue, key: date)
            let service = hmac(string: self.service, key: region)
            let string = stringToSign(
                url: url,
                headers: headers,
                datetime: datetime,
                method: method,
                bodyDigest: bodyDigest
            )

            return hmac(string: string, key: hmac(string: identifier, key: service)).hexdigest()
        }

        func credentialScope(_ datetime: String) -> String {
            return [
                String(datetime.prefix(upTo: datetime.index(datetime.startIndex, offsetBy: 8))),
                region.rawValue,
                service,
                identifier
            ].joined(separator: "/")
        }

        func stringToSign(url: URL, headers: [String: String], datetime: String, method: String, bodyDigest: String) -> String {
            let canonicalRequestString = canonicalRequest(
                url: URLComponents(url: url, resolvingAgainstBaseURL: true)!,
                headers: headers,
                method: method,
                bodyDigest: bodyDigest
            )

            var canonicalRequestBytes = Array(canonicalRequestString.utf8)

            return [
                "AWS4-HMAC-SHA256",
                datetime,
                credentialScope(datetime),
                sha256(&canonicalRequestBytes).hexdigest(),
            ].joined(separator: "\n")
        }

        func canonicalRequest(url: URLComponents, headers: [String: String], method: String, bodyDigest: String) -> String {
            let query = { () -> String in
                guard let q = url.percentEncodedQuery else {
                    return ""
                }
                if !q.contains("=") {
                    return "\(q)="
                }
                
                return q
            }()
            
            return [
                method,
                V4.awsUriEncode(url.path, encodeSlash: false),
                query,
                "\(canonicalHeaders(headers))\n",
                signedHeaders(headers),
                bodyDigest
            ].joined(separator: "\n")
        }

        private static let awsUriAllowed: [String] = [
            "_", "-", "~", ".",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"
        ]

        private static let awsUriAllowedUTF8: Set<UTF8.CodeUnit> = Set<UTF8.CodeUnit>(awsUriAllowed.map { $0.utf8[$0.startIndex] })

        /// Encode URI according to https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
        class func awsUriEncode(_ str: String, encodeSlash: Bool = true) -> String {
            var result = ""
            for char in str.utf8 {
                let charStr = String(UnicodeScalar(char))
                if awsUriAllowedUTF8.contains(char) {
                    result.append(charStr)
                } else if charStr == "/" {
                    result.append(encodeSlash ? "%2F" : charStr)
                } else {
                    result.append("%")
                    result.append(String(format:"%02X", char))
                }
            }
            return result
        }
    }
}


extension Collection where Iterator.Element == URLQueryItem {
    var asStringForURL: String {
        return self.compactMap({ "\($0.name)=\($0.value ?? "")" }).joined(separator: "&")
    }
}
