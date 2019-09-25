//
//  AWSClient.swift
//  AWSSDKSwift
//
//  Created by Jonathan McAllister on 2018/10/13.
//
//

import Foundation
import NIOHTTP1
import XCTest
@testable import AWSSDKSwiftCore

class AWSClientTests: XCTestCase {
    struct C: AWSShape {
        public static var members: [AWSShapeMember] = [
            AWSShapeMember(label: "value", required: true, type: .string)
        ]

        let value = "<html><body><a href=\"https://redsox.com\">Test</a></body></html>"
    }

    struct E: AWSShape {
        public static var members: [AWSShapeMember] = [
            AWSShapeMember(label: "Member", required: true, type: .list(flat: false)),
        ]

        let Member = ["memberKey": "memberValue", "memberKey2": "memberValue2"]

        private enum CodingKeys: String, CodingKey {
            case Member = "Member"
        }
    }

    struct F: AWSShape {
        public static let payloadPath: String? = "fooParams"

        public static var members: [AWSShapeMember] = [
            AWSShapeMember(label: "Member", required: true, type: .list(flat: false)),
            AWSShapeMember(label: "fooParams", required: false, type: .structure),
        ]

        public let fooParams: E?

        public init(fooParams: E? = nil) {
            self.fooParams = fooParams
        }

        private enum CodingKeys: String, CodingKey {
            case fooParams = "fooParams"
        }

    }

    func testCreateAWSRequest() {
        let input = C()

        let sesClient = AWSClient(
            accessKeyId: "foo",
            secretAccessKey: "bar",
            region: nil,
            service: "email",
            serviceProtocol: ServiceProtocol(type: .query),
            apiVersion: "2013-12-01",
            middlewares: [],
            possibleErrorTypes: [SESErrorType.self]
        )

        do {
            let awsRequest = try sesClient.debugCreateAWSRequest(
                operation: "SendEmail",
                path: "/",
                httpMethod: "POST",
                input: input
            )
            XCTAssertEqual(awsRequest.url.absoluteString, "\(sesClient.endpoint)/")
            XCTAssertEqual(String(describing: awsRequest.body), "text(\"Action=SendEmail&Version=2013-12-01&value=%3Chtml%3E%3Cbody%3E%3Ca%20href%3D%22https://redsox.com%22%3ETest%3C/a%3E%3C/body%3E%3C/html%3E\")")
            let nioRequest = try awsRequest.toNIORequest()
            XCTAssertEqual(nioRequest.head.headers["Content-Type"][0], "application/x-www-form-urlencoded")
        } catch {
            XCTFail(error.localizedDescription)
        }

        let kinesisClient = AWSClient(
            accessKeyId: "foo",
            secretAccessKey: "bar",
            region: nil,
            amzTarget: "Kinesis_20131202",
            service: "kinesis",
            serviceProtocol: ServiceProtocol(type: .json, version: ServiceProtocol.Version(major: 1, minor: 1)),
            apiVersion: "2013-12-02",
            middlewares: [],
            possibleErrorTypes: [KinesisErrorType.self]
        )

        do {
            let awsRequest = try kinesisClient.debugCreateAWSRequest(
                operation: "PutRecord",
                path: "/",
                httpMethod: "POST",
                input: input
            )
            XCTAssertEqual(awsRequest.url.absoluteString, "\(kinesisClient.endpoint)/")
            let nioRequest = try awsRequest.toNIORequest()
            XCTAssertEqual(nioRequest.head.headers["Content-Type"][0], "application/x-amz-json-1.1")
        } catch {
            XCTFail(error.localizedDescription)
        }

        let s3Client = AWSClient(
            accessKeyId: "foo",
            secretAccessKey: "bar",
            region: nil,
            service: "s3",
            serviceProtocol: ServiceProtocol(type: .restxml),
            apiVersion: "2006-03-01",
            endpoint: nil,
            serviceEndpoints: ["us-west-2": "s3.us-west-2.amazonaws.com", "eu-west-1": "s3.eu-west-1.amazonaws.com", "us-east-1": "s3.amazonaws.com", "ap-northeast-1": "s3.ap-northeast-1.amazonaws.com", "s3-external-1": "s3-external-1.amazonaws.com", "ap-southeast-2": "s3.ap-southeast-2.amazonaws.com", "sa-east-1": "s3.sa-east-1.amazonaws.com", "ap-southeast-1": "s3.ap-southeast-1.amazonaws.com", "us-west-1": "s3.us-west-1.amazonaws.com"],
            partitionEndpoint: "us-east-1",
            middlewares: [],
            possibleErrorTypes: [S3ErrorType.self]
        )

        do {
            let awsRequest = try s3Client.debugCreateAWSRequest(
                operation: "ListObjectsV2",
                path: "/Bucket?list-type=2",
                httpMethod: "GET",
                input: input
            )

            XCTAssertEqual(awsRequest.url.absoluteString, "https://s3.amazonaws.com/Bucket?list-type=2")
            _ = try awsRequest.toNIORequest()
        } catch {
            XCTFail(error.localizedDescription)
        }

        // encode Shape with payloadPath
        //
        let input2 = E()
        let input3 = F(fooParams: input2)

        // encode for restxml
        //
        do {
            let awsRequest = try s3Client.debugCreateAWSRequest(
                operation: "payloadPath",
                path: "/Bucket?list-type=2",
                httpMethod: "POST",
                input: input3
            )

            XCTAssertNotNil(awsRequest.body)
            if let xmlData = try awsRequest.body.asData() {
                let xmlNode = try XML2Parser(data: xmlData).parse()
                let json = XMLNodeSerializer(node: xmlNode).serializeToJSON()
                let json_data = json.data(using: .utf8)!
                let dict = try! JSONSerializer().serializeToDictionary(json_data)
                let fromJson = dict["E"]! as! [String: String]
                XCTAssertEqual(fromJson["MemberKey"], "memberValue")
            }
            _ = try awsRequest.toNIORequest()
        } catch {
            XCTFail(error.localizedDescription)
        }

        // encode for json
        //
        do {
            let awsRequest = try kinesisClient.debugCreateAWSRequest(
                operation: "PutRecord",
                path: "/",
                httpMethod: "POST",
                input: input3
            )
            XCTAssertNotNil(awsRequest.body)
            if let jsonData = try awsRequest.body.asData() {
                let jsonBody = try! JSONSerialization.jsonObject(with: jsonData, options: .allowFragments) as! [String:Any]
                let fromJson = jsonBody["Member"]! as! [String: String]
                XCTAssertEqual(fromJson["memberKey"], "memberValue")
            }

        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    static var allTests : [(String, (AWSClientTests) -> () throws -> Void)] {
        return [
            ("testCreateAWSRequest", testCreateAWSRequest)
        ]
    }
}

/// Error enum for Kinesis
public enum KinesisErrorType: AWSErrorType {
    case resourceNotFoundException(message: String?)
}

extension KinesisErrorType {
    public init?(errorCode: String, message: String?){
        var errorCode = errorCode
        if let index = errorCode.firstIndex(of: "#") {
            errorCode = String(errorCode[errorCode.index(index, offsetBy: 1)...])
        }
        switch errorCode {
        case "ResourceNotFoundException":
            self = .resourceNotFoundException(message: message)
        default:
            return nil
        }
    }
}

/// Error enum for SES
public enum SESErrorType: AWSErrorType {
    case messageRejected(message: String?)
}

extension SESErrorType {
    public init?(errorCode: String, message: String?){
        var errorCode = errorCode
        if let index = errorCode.firstIndex(of: "#") {
            errorCode = String(errorCode[errorCode.index(index, offsetBy: 1)...])
        }
        switch errorCode {
        case "MessageRejected":
            self = .messageRejected(message: message)
        default:
            return nil
        }
    }
}

/// Error enum for S3
public enum S3ErrorType: AWSErrorType {
    case noSuchKey(message: String?)
}

extension S3ErrorType {
  public init?(errorCode: String, message: String?){
      var errorCode = errorCode
    if let index = errorCode.firstIndex(of: "#") {
          errorCode = String(errorCode[errorCode.index(index, offsetBy: 1)...])
      }
      switch errorCode {
      case "NoSuchKey":
          self = .noSuchKey(message: message)
      default:
          return nil
      }
  }
}
