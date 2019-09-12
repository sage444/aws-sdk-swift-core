//
//  Client.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/03/13.
//
//

import Foundation
import Dispatch
import NIO
import NIOHTTP1
import HypertextApplicationLanguage

extension String {
    public static let uriAWSQueryAllowed: [String] = ["&", "\'", "(", ")", "-", ".", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "=", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
}

public struct InputContext {
    let Shape: AWSShape.Type
    let input: AWSShape
}

public struct AWSClient {

    public enum RequestError: Error {
        case invalidURL(String)
    }

    let signer: Signers.V4

    let apiVersion: String

    let amzTarget: String?

    let _endpoint: String?

    let serviceProtocol: ServiceProtocol

    let serviceEndpoints: [String: String]

    let partitionEndpoint: String?
    
    var credProviders: [CredentialProvider?] {
        return [SharedCredential(), EnvironementCredential(), RuntimeCredentials()]
    }

    public let middlewares: [AWSRequestMiddleware]

    public var possibleErrorTypes: [AWSErrorType.Type]

    public var endpoint: String {
        if let givenEndpoint = self._endpoint {
            return givenEndpoint
        }
        return "https://\(serviceHost)"
    }

    public var serviceHost: String {
        if let serviceEndpoint = serviceEndpoints[signer.region.rawValue] {
            return serviceEndpoint
        }

        if let partitionEndpoint = partitionEndpoint, let globalEndpoint = serviceEndpoints[partitionEndpoint] {
            return globalEndpoint
        }
        return "\(signer.service).\(signer.region.rawValue).amazonaws.com"
    }
    
    public static let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)

    public init(accessKeyId: String? = nil, secretAccessKey: String? = nil, region givenRegion: Region?, amzTarget: String? = nil, service: String, serviceProtocol: ServiceProtocol, apiVersion: String, endpoint: String? = nil, serviceEndpoints: [String: String] = [:], partitionEndpoint: String? = nil, middlewares: [AWSRequestMiddleware] = [], possibleErrorTypes: [AWSErrorType.Type]? = nil, credetialProviders: [CredentialProvider?] = [SharedCredential(), EnvironementCredential(), RuntimeCredentials()]) {

        let credential = credetialProviders.compactMap({ return $0 }).first
        
        let region: Region
        if let _region = givenRegion {
            region = _region
        }
        else if let partitionEndpoint = partitionEndpoint, let reg = Region(rawValue: partitionEndpoint) {
            region = reg
        } else if let defaultRegion = ProcessInfo.processInfo.environment["AWS_DEFAULT_REGION"], let reg = Region(rawValue: defaultRegion) {
            region = reg
        } else {
            region = .useast1
        }

        self.signer = Signers.V4(credential: credential, region: region, service: service)
        self.apiVersion = apiVersion
        self._endpoint = endpoint
        self.amzTarget = amzTarget
        self.serviceProtocol = serviceProtocol
        self.serviceEndpoints = serviceEndpoints
        self.partitionEndpoint = partitionEndpoint
        self.middlewares = middlewares
        self.possibleErrorTypes = possibleErrorTypes ?? []
    }
}

// invoker
extension AWSClient {
    fileprivate func invoke(_ nioRequest: Request) throws -> Response {
//        print("<<< \(nioRequest)")
        let client = HTTPClient(hostname: nioRequest.head.headers["Host"].first!, port: 443, eventGroup: AWSClient.eventLoopGroup)
        let future = try client.connect(nioRequest)

        //TODO(jmca) don't block
        let response = try future.wait()

        client.close { error in
            if let error = error {
                print("Error closing connection: \(error)")
            }
        }

        return response
    }

    //TODO(jmca) learn how to map response to validate and return
    // a future of generic Output: AWSShape
    fileprivate func invokeAsync(_ nioRequest: Request) throws -> EventLoopFuture<Response>{
        let client = HTTPClient(hostname: nioRequest.head.headers["Host"].first!, port: 443, eventGroup: AWSClient.eventLoopGroup)
        let future = try client.connect(nioRequest)
        future.whenComplete { _ in 
          client.close { error in
              if let error = error {
                  print("Error closing connection: \(error)")
              }
          }
        }
        return future
    }
}

// public facing apis
extension AWSClient {
    public func send<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) throws {
        let awsRequest = try createAWSRequest(
            operation: operationName,
            path: path,
            httpMethod: httpMethod,
            input: input
        )
        let nioRequest = try createNioRequest(awsRequest)
        _ = try self.invoke(nioRequest)
    }

    public func send(operation operationName: String, path: String, httpMethod: String) throws {
        let awsRequest = createAWSRequest(operation: operationName, path: path, httpMethod: httpMethod)
        let nioRequest = try createNioRequest(awsRequest)
        _ = try self.invoke(nioRequest)
    }

    public func send<Output: AWSShape>(operation operationName: String, path: String, httpMethod: String) throws -> Output {
        let awsRequest = createAWSRequest(operation: operationName, path: path, httpMethod: httpMethod)
        let nioRequest = try createNioRequest(awsRequest)
        return try validate(operation: operationName, response: try self.invoke(nioRequest))
    }

    public func send<Output: AWSShape, Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input)
        throws -> Output {
        let awsRequest = try createAWSRequest(
            operation: operationName,
            path: path,
            httpMethod: httpMethod,
            input: input
        )
        let nioRequest = try createNioRequest(awsRequest)
        return try validate(operation: operationName, response: try self.invoke(nioRequest))
    }
}

// request creator
extension AWSClient {
    func createNIORequestWithSignedURL(_ request: AWSRequest) throws -> Request {
        var nioRequest = try request.toNIORequest()
        let head = nioRequest.head
        if let unsignedUrl = URL(string: head.uri) {
            let signedURI = signer.signedURL(url: unsignedUrl)
            nioRequest.head.uri = signedURI.absoluteString
            nioRequest.head.headers.replaceOrAdd(name: "Host", value: unsignedUrl.hostWithPort!)
//            if let token = signer.credential?.sessionToken {
//                nioRequest.head.headers.replaceOrAdd(name: "X-Amz-Security-Token", value: token)
//            }
        }
        return try nioRequestWithSignedHeader(nioRequest)
    }

    func createNIORequestWithSignedHeader(_ request: AWSRequest) throws -> Request {
        return try nioRequestWithSignedHeader(request.toNIORequest())
    }

    func nioRequestWithSignedHeader(_ nioRequest: Request) throws -> Request {
        if signer.credential == nil || (signer.credential?.isEmpty() ?? true) || (signer.credential?.nearExpiration() ?? true) {
            signer.credential = credProviders.compactMap({ $0 }).filter({ !($0.isEmpty() || $0.nearExpiration()) }).first
        }
        
        var nioRequest = nioRequest
        // TODO avoid copying
        var headers: [String: String] = [:]
        for (key, value) in nioRequest.head.headers {
            headers[key.description] = value
        }

        let method = { () -> String in
            switch nioRequest.head.method {
            case HTTPMethod.RAW(value: "HEAD"): return "HEAD"
            case HTTPMethod.RAW(value: "GET"): return "GET"
            case HTTPMethod.RAW(value: "POST"): return "POST"
            case HTTPMethod.RAW(value: "PUT"): return "PUT"
            case HTTPMethod.RAW(value: "PATCH"): return "PATCH"
            case HTTPMethod.RAW(value: "DELETE"): return "DELETE"
            default: return "GET"
            }
        }()

        guard let url = URL(string: nioRequest.head.uri) else {
            fatalError("nioRequest.head.uri is invalid.")
        }

        let signedHeaders = signer.signedHeaders(
            url: url,
            headers: headers,
            method: method,
            bodyData: nioRequest.body
        )

        for (key, value) in signedHeaders {
            nioRequest.head.headers.replaceOrAdd(name: key, value: value)
        }

        return nioRequest
    }

    public func createNioRequest(_ request: AWSRequest) throws -> Request {
//        let nioRequest: Request
//        switch request.httpMethod {
//        case "GET":
//            switch serviceProtocol.type {
//            case .restjson:
//                nioRequest = try createNIORequestWithSignedHeader(request)
//
//            default:
//                nioRequest = try createNIORequestWithSignedURL(request)
//            }
//        default:
//            nioRequest = try createNIORequestWithSignedHeader(request)
//        }
//        return nioRequest
        return try createNIORequestWithSignedHeader(request)
    }

    fileprivate func createAWSRequest(operation operationName: String, path: String, httpMethod: String) -> AWSRequest {
        return AWSRequest(
            region: self.signer.region,
            url: URL(string:  "\(endpoint)\(path)")!,
            serviceProtocol: serviceProtocol,
            service: signer.service,
            amzTarget: amzTarget,
            operation: operationName,
            httpMethod: httpMethod,
            httpHeaders: [:],
            body: .empty,
            middlewares: middlewares
        )
    }

    public func createAWSRequest<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) throws -> AWSRequest {
        var headers: [String: String] = [:]
        var path = path
        var urlComponents = URLComponents()
        var body: Body = .empty
        var queryParams: [String: Any] = [:]

        guard let ep = URL(string: "\(endpoint)") else {
            throw RequestError.invalidURL("\(endpoint)")
        }

        urlComponents.scheme = ep.scheme
        urlComponents.host = ep.host

        // TODO should replace with Encodable
        let mirror = Mirror(reflecting: input)

        for (key, value) in Input.headerParams {
            if let attr = mirror.getAttribute(forKey: value.toSwiftVariableCase()) {
                headers[key] = "\(attr)"
            }
        }

        for (key, value) in Input.queryParams {
            if let attr = mirror.getAttribute(forKey: value.toSwiftVariableCase()) {
                queryParams[key] = "\(attr)"
            }
        }

        for (key, value) in Input.pathParams {
            if let attr = mirror.getAttribute(forKey: value.toSwiftVariableCase()) {
                path = path
                    .replacingOccurrences(of: "{\(key)}", with: "\(attr)")
                    // percent-encode key which is part of the path
                    .replacingOccurrences(of: "{\(key)+}", with: "\(attr)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)
            }
        }

        switch serviceProtocol.type {
        case .json, .restjson:
            if let payload = Input.payloadPath, let payloadBody = mirror.getAttribute(forKey: payload.toSwiftVariableCase()) {
                switch payloadBody {
                case is AWSShape:
                    let inputBody: Body = .json(try AWSShapeEncoder().encodeToJSONUTF8Data(input))
                    if let inputDict = try inputBody.asDictionary(), let payloadDict = inputDict[payload] {
                        body = .json(try JSONSerialization.data(withJSONObject: payloadDict))
                    }
                default:
                    body = Body(anyValue: payloadBody)
                }
                headers.removeValue(forKey: payload.toSwiftVariableCase())
            } else {
                body = .json(try AWSShapeEncoder().encodeToJSONUTF8Data(input))
            }

        case .query:
            let data = try AWSShapeEncoder().encodeToJSONUTF8Data(input)
            var dict = try JSONSerializer().serializeToFlatDictionary(data)

            dict["Action"] = operationName
            dict["Version"] = apiVersion

            switch httpMethod {
            case "GET":
                queryParams = queryParams.merging(dict) { $1 }
            default:
                if let urlEncodedQueryParams = urlEncodeQueryParams(fromDictionary: dict) {
                    body = .text(urlEncodedQueryParams)
                }
            }

        case .restxml:
            if let payload = Input.payloadPath, let payloadBody = mirror.getAttribute(forKey: payload.toSwiftVariableCase()) {
                switch payloadBody {
                case let pb as AWSShape:
                    body = .xml(try AWSShapeEncoder().encodeToXMLNode(pb))
                default:
                    body = Body(anyValue: payloadBody)
                }
                headers.removeValue(forKey: payload.toSwiftVariableCase())
            } else {
                body = .xml(try AWSShapeEncoder().encodeToXMLNode(input))
            }

        case .other(let proto):
            switch proto.lowercased() {
            case "ec2":
                let data = try AWSShapeEncoder().encodeToJSONUTF8Data(input)
                var params = try JSONSerializer().serializeToDictionary(data)
                params["Action"] = operationName
                params["Version"] = apiVersion
                body = .text(params.map({ "\($0.key)=\($0.value)" }).joined(separator: "&"))
            default:
                break
            }
        }

        guard let parsedPath = URLComponents(string: path) else {
            throw RequestError.invalidURL("\(endpoint)\(path)")
        }

        urlComponents.path = parsedPath.path

        if let pathQueryItems = parsedPath.queryItems {
            for item in pathQueryItems { // BUG: Losing parameters without value, for example on s3 "key?uploads"
                queryParams[item.name] = item.value
            }
        }
        
        var prepared = urlQueryItems(fromDictionary: queryParams) ?? []
        if let pathQueryItems = parsedPath.queryItems {
            prepared.append(contentsOf: pathQueryItems)
        }
        prepared.sort { $0.name < $1.name }
        if prepared.count > 0 {
            urlComponents.queryItems = prepared
        } else {
            urlComponents.queryItems = nil
        }
        guard let url = urlComponents.url else {
            throw RequestError.invalidURL("\(endpoint)\(path)")
        }

        return AWSRequest(
            region: self.signer.region,
            url: url,
            serviceProtocol: serviceProtocol,
            service: signer.service,
            amzTarget: amzTarget,
            operation: operationName,
            httpMethod: httpMethod,
            httpHeaders: headers,
            body: body,
            middlewares: middlewares
        )
    }

    fileprivate func urlEncodeQueryParams(fromDictionary dict: [String:Any]) -> String? {
        var components = URLComponents()
        components.queryItems = urlQueryItems(fromDictionary: dict)
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        if components.queryItems != nil, let url = components.url {
            return url.query
        }
        return nil
    }

    fileprivate func urlQueryItems(fromDictionary dict: [String:Any]) -> [URLQueryItem]? {
        var queryItems: [URLQueryItem] = []
        let keys = Array(dict.keys).sorted()

        for key in keys {
            if let value = dict[key] {
                queryItems.append(URLQueryItem(name: key, value: String(describing: value)))
            }
        }
        return queryItems.isEmpty ? nil : queryItems
    }
}

// debug request creator
#if DEBUG
extension AWSClient {
    func debugCreateAWSRequest<Input: AWSShape>(operation operationName: String, path: String, httpMethod: String, input: Input) throws -> AWSRequest {
        return try createAWSRequest(operation: operationName, path: path, httpMethod: httpMethod, input: input)
    }
}
#endif

// response validator
extension AWSClient {
    public func validate<Output: AWSShape>(operation operationName: String, response: Response) throws -> Output {

        guard (200..<300).contains(response.head.status.code) else {
            let responseBody = try validateBody(
                for: response,
                payloadPath: nil,
                members: Output._members
            )
            throw createError(for: response, withComputedBody: responseBody, withRawData: response.body)
        }

        let responseBody = try validateBody(
            for: response,
            payloadPath: Output.payloadPath,
            members: Output._members
        )

        var responseHeaders: [String: String] = [:]
        for (key, value) in response.head.headers {
            responseHeaders[key.description] = value
        }

        var outputDict: [String: Any] = [:]
        switch responseBody {
        case .json(let data):
            outputDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]

        case .xml(let node):
            let str = XMLNodeSerializer(node: node).serializeToJSON()
            outputDict = try JSONSerialization.jsonObject(with: str.data(using: .utf8)!, options: []) as? [String: Any] ?? [:]

            if let childOutputDict = outputDict[operationName+"Response"] as? [String: Any] {
                outputDict = childOutputDict
                if let childOutputDict = outputDict[operationName+"Result"] as? [String: Any] {
                    outputDict = childOutputDict
                }
            } else {
                if let key = outputDict.keys.first, let dict = outputDict[key] as? [String: Any] {
                    outputDict = dict
                }
            }

        case .buffer(let data):
            if let payload = Output.payloadPath {
                outputDict[payload] = data
            }

        case .text(let text):
            if let payload = Output.payloadPath {
                outputDict[payload] = text
            }

        default:
            break
        }

        for (key, value) in response.head.headers {
            let headeParams = Output.headerParams
            if let index = headeParams.firstIndex(where: { $0.key.lowercased() == key.description.lowercased() }) {
                let outDicKey = headeParams[index].key
                if let number = Double(value) {
                    outputDict[outDicKey] = number.truncatingRemainder(dividingBy: 1) == 0 ? Int(number) : number
                } else if let boolean = Bool(value) {
                    outputDict[outDicKey] = boolean
                } else {
                    outputDict[outDicKey] = value
                }
            }
        }

        return try DictionaryDecoder().decode(Output.self, from: outputDict)
    }

    private func validateBody(for response: Response, payloadPath: String?, members: [AWSShapeMember]) throws -> Body {
        var responseBody: Body = .empty
        let data = response.body

        if data.isEmpty {
            return responseBody
        }

        if payloadPath != nil {
            return .buffer(data)
        }

        switch serviceProtocol.type {
        case .json, .restjson:
            if let cType = response.contentType(), cType.contains("hal+json") {
                let representation = try Representation.from(json: data)
                var dictionary = representation.properties
                for rel in representation.rels {
                    guard let representations = try Representation.from(json: data).representations(for: rel) else {
                        continue
                    }

                    guard let hint = members.filter({ $0.location?.name == rel }).first else {
                        continue
                    }

                    switch hint.type {
                    case .list:
                        let properties : [[String: Any]] = try representations.map({
                            var props = $0.properties
                            var linkMap: [String: [Link]] = [:]

                            for link in $0.links {
                                let key = link.rel.camelCased(separator: ":")
                                if linkMap[key] == nil {
                                    linkMap[key] = []
                                }
                                linkMap[key]?.append(link)
                            }

                            for (key, links) in linkMap {
                                var dict: [String: Any] = [:]
                                for link in links {
                                    guard let name = link.name else { continue }
                                    let head = HTTPRequestHead(version: HTTPVersion(major: 1, minor: 1), method: .GET, uri: endpoint + link.href)
                                    let res = try invoke(nioRequestWithSignedHeader(Request(head: head, body: Data())))
                                    let representaion = try Representation().from(json: res.body)
                                    dict[name] = representaion.properties
                                }
                                props[key] = dict
                            }

                            return props
                        })
                        dictionary[rel] = properties

                    default:
                        dictionary[rel] = representations.map({ $0.properties }).first ?? [:]
                    }
                }
                responseBody = .json(try JSONSerialization.data(withJSONObject: dictionary, options: []))

            } else {
                responseBody = .json(data)
            }

        case .restxml, .query:
            let xmlNode = try XML2Parser(data: data).parse()
            responseBody = .xml(xmlNode)

        case .other(let proto):
            switch proto.lowercased() {
            case "ec2":
                let xmlNode = try XML2Parser(data: data).parse()
                responseBody = .xml(xmlNode)

            default:
                responseBody = .buffer(data)
            }
        }

        return responseBody
    }

    private func createError(for response: Response, withComputedBody body: Body, withRawData data: Data) -> Error {
        let bodyDict: [String: Any] = (try? body.asDictionary()) ?? [:]
        var code: String?
        var message: String?

        switch serviceProtocol.type {
        case .query:
            guard let dict = bodyDict["ErrorResponse"] as? [String: Any] else {
                break
            }
            let errorDict = dict["Error"] as? [String: Any]
            code = errorDict?["Code"] as? String
            message = errorDict?["Message"] as? String

        case .restxml:
            let errorDict = bodyDict["Error"] as? [String: Any]
            code = errorDict?["Code"] as? String
            message = errorDict?.filter({ $0.key != "Code" })
                .map({ "\($0.key): \($0.value)"})
                .joined(separator: ", ")

        case .restjson:
            code = response.head.headers.filter( { $0.name == "x-amzn-ErrorType"}).first?.value
            message = bodyDict.filter({ $0.key.lowercased() == "message" }).first?.value as? String

        case .json:
            code = bodyDict["__type"] as? String
            message = bodyDict.filter({ $0.key.lowercased() == "message" }).first?.value as? String

        default:
            break
        }

        if let errorCode = code {
            for errorType in possibleErrorTypes {
                if let error = errorType.init(errorCode: errorCode, message: message) {
                    return error
                }
            }

            if let error = AWSClientError(errorCode: errorCode, message: message) {
                return error
            }

            if let error = AWSServerError(errorCode: errorCode, message: message) {
                return error
            }

            return AWSResponseError(errorCode: errorCode, message: message)
        }

        return AWSError(message: message ?? "Unhandled Error", rawBody: String(data: data, encoding: .utf8) ?? "")
    }
}

extension AWSClient.RequestError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidURL(let urlString):
            return """
            The request url \(urlString) is invalid format.
            This error is internal. So please make a issue on https://github.com/noppoMan/aws-sdk-swift/issues to solve it.
            """
        }
    }
}
