//
//  DictionarySerializer.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/06.
//
//

import Foundation
import NIO
import NIOHTTP1
import XCTest
@testable import AWSSDKSwiftCore

class HTTPClientTests: XCTestCase {

      static var allTests : [(String, (HTTPClientTests) -> () throws -> Void)] {
          return [
              ("testInitWithInvalidURL", testInitWithInvalidURL),
              ("testInitWithValidRL", testInitWithValidRL),
              ("testConnectSimpleGet", testConnectSimpleGet),
              ("testConnectGet", testConnectGet),
              ("testConnectPost", testConnectPost)
          ]
      }
    
    static let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    
    func testInitWithInvalidURL() {
      do {
        _ = try HTTPClient(url: URL(string: "no_protocol.com")!, eventGroup: HTTPClientTests.eventLoop)
          XCTFail("Should throw malformedURL error")
      } catch {
        if case HTTPClientError.malformedURL = error {}
        else {
            XCTFail("Should throw malformedURL error")
        }
      }
    }

    func testInitWithValidRL() {
      do {
          _ = try HTTPClient(url: URL(string: "https://kinesis.us-west-2.amazonaws.com/")!, eventGroup: HTTPClientTests.eventLoop)
      } catch {
          XCTFail("Should not throw malformedURL error")
      }

      do {
          _ = try HTTPClient(url: URL(string: "http://169.254.169.254/latest/meta-data/iam/security-credentials/")!, eventGroup: HTTPClientTests.eventLoop)
      } catch {
          XCTFail("Should not throw malformedURL error")
      }
    }

    func testInitWithHostAndPort() {
        let url = URL(string: "https://kinesis.us-west-2.amazonaws.com/")!
        _ = try! HTTPClient(url: url, eventGroup: HTTPClientTests.eventLoop)
    }

    func testConnectSimpleGet() {
      do {
          let url = URL(string: "https://kinesis.us-west-2.amazonaws.com/")!
        let client = try HTTPClient(url: url, eventGroup: HTTPClientTests.eventLoop)
          let head = HTTPRequestHead(
                       version: HTTPVersion(major: 1, minor: 1),
                       method: .GET,
                       uri: url.path
                     )
          let request = Request(head: head, body: Data())
          let future = try client.connect(request)
          future.whenSuccess { response in }
          future.whenFailure { error in }
          future.whenComplete { _ in }
      } catch {
          XCTFail("Should not throw error")
      }

      do {
          _ = try HTTPClient(url: URL(string: "http://169.254.169.254/latest/meta-data/iam/security-credentials/")!, eventGroup: HTTPClientTests.eventLoop)
      } catch {
          XCTFail("Should not throw malformedURL error")
      }
    }

    func testConnectGet() {
      do {
          let url = URL(string: "https://kinesis.us-west-2.amazonaws.com/")!
        let client = try HTTPClient(url: url, eventGroup: HTTPClientTests.eventLoop)
          let head = HTTPRequestHead(
                       version: HTTPVersion(major: 1, minor: 1),
                       method: .GET,
                       uri: url.path
                     )
          let request = Request(head: head, body: Data())
          let future = try client.connect(request)
          future.whenSuccess { response in }
          future.whenFailure { error in }
          future.whenComplete { _ in }
      } catch {
          XCTFail("Should not throw error")
      }

      do {
          _ = try HTTPClient(url: URL(string: "http://169.254.169.254/latest/meta-data/iam/security-credentials/")!, eventGroup: HTTPClientTests.eventLoop)
      } catch {
          XCTFail("Should not throw malformedURL error")
      }
    }

    func testConnectPost() {
      do {
          let url = URL(string: "https://kinesis.us-west-2.amazonaws.com/")!
        let client = try HTTPClient(url: url, eventGroup: HTTPClientTests.eventLoop)
          let head = HTTPRequestHead(
                       version: HTTPVersion(major: 1, minor: 1),
                       method: .GET,
                       uri: url.path
                     )
          let request = Request(head: head, body: Data())
          let future = try client.connect(request)
          future.whenSuccess { response in }
          future.whenFailure { error in }
          future.whenComplete { _ in }
      } catch {
        XCTFail("Should not throw error")
      }

      do {
          _ = try HTTPClient(url: URL(string: "http://169.254.169.254/latest/meta-data/iam/security-credentials/")!, eventGroup: HTTPClientTests.eventLoop)
      } catch {
        XCTFail("Should not throw malformedURL error")
      }
    }

}
