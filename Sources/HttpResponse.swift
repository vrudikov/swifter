//
//  HttpResponse.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

#if os(Linux)
    import Glibc
#else
    import Foundation
#endif

public enum SerializationError: ErrorType {
    case InvalidObject
    case NotSupported
}

public protocol HttpResponseBodyWriter {
    func write(file: File) throws
    func write(data: [UInt8]) throws
    func write(data: ArraySlice<UInt8>) throws
}

public enum HttpResponseBody {
    
    case Json(AnyObject)
    case Html(String)
    case Text(String)
    case Custom(AnyObject, (Any) throws -> String)
    
    func content() -> (Int, (HttpResponseBodyWriter throws -> Void)?) {
        do {
            print(String(self))
            let response: ResponseProtocol;
            switch self {
            case .Json(let object):
                let response = JsonResponse(contentObject: object)
            case .Text(let body):
                let response = TextResponse(contentObject: object!)
            case .Html(let body):
                let response = HtmlResponse(contentObject: object!)
            case .Custom(let object, let closure):
                let response = CustomResponse(contentObject: object, closure: closure)
            default:
                let response = Response(contentObject: "")
            }
            
            let content = response.content()
            return (content.contentLength, {
                try $0.write(content)
            })
        } catch {
            let data = [UInt8]("Serialisation error: \(error)".utf8)
            return (data.count, {
                try $0.write(data)
            })
        }
    }
}

public enum HttpResponse {
    
    case SwitchProtocols([String: String], Socket -> Void)
    case OK(HttpResponseBody), Created, Accepted
    case MovedPermanently(String)
    case BadRequest(HttpResponseBody?), Unauthorized, Forbidden, NotFound
    case InternalServerError
    case RAW(Int, String, [String:String]?, (HttpResponseBodyWriter throws -> Void)? )

    func statusCode() -> Int {
        switch self {
        case .SwitchProtocols(_, _)   : return 101
        case .OK(_)                   : return 200
        case .Created                 : return 201
        case .Accepted                : return 202
        case .MovedPermanently        : return 301
        case .BadRequest(_)           : return 400
        case .Unauthorized            : return 401
        case .Forbidden               : return 403
        case .NotFound                : return 404
        case .InternalServerError     : return 500
        case .RAW(let code, _ , _, _) : return code
        }
    }
    
    func reasonPhrase() -> String {
        switch self {
        case .SwitchProtocols(_, _)    : return "Switching Protocols"
        case .OK(_)                    : return "OK"
        case .Created                  : return "Created"
        case .Accepted                 : return "Accepted"
        case .MovedPermanently         : return "Moved Permanently"
        case .BadRequest(_)            : return "Bad Request"
        case .Unauthorized             : return "Unauthorized"
        case .Forbidden                : return "Forbidden"
        case .NotFound                 : return "Not Found"
        case .InternalServerError      : return "Internal Server Error"
        case .RAW(_, let phrase, _, _) : return phrase
        }
    }
    
    func headers() -> [String: String] {
        var headers = ["Server" : "Swifter \(HttpServer.VERSION)"]
        switch self {
        case .SwitchProtocols(let switchHeaders, _):
            for (key, value) in switchHeaders {
                headers[key] = value
            }
        case .OK(let body):
            switch body {
            case .Json(_)   : headers["Content-Type"] = "application/json"
            case .Html(_)   : headers["Content-Type"] = "text/html"
            default:break
            }
        case .MovedPermanently(let location):
            headers["Location"] = location
        case .RAW(_, _, let rawHeaders, _):
            if let rawHeaders = rawHeaders {
                for (k, v) in rawHeaders {
                    headers.updateValue(v, forKey: k)
                }
            }
        default:break
        }
        return headers
    }
    
    func content() -> (length: Int, write: (HttpResponseBodyWriter throws -> Void)?) {
        switch self {
        case .OK(let body)             : return body.content()
        case .BadRequest(let body)     : return body?.content() ?? (-1, nil)
        case .RAW(_, _, _, let writer) : return (-1, writer)
        default                        : return (-1, nil)
        }
    }
    
    func socketSession() -> (Socket -> Void)?  {
        switch self {
        case SwitchProtocols(_, let handler) : return handler
        default: return nil
        }
    }
}

/**
    Makes it possible to compare handler responses with '==', but
	ignores any associated values. This should generally be what
	you want. E.g.:
	
    let resp = handler(updatedRequest)
        if resp == .NotFound {
        print("Client requested not found: \(request.url)")
    }
*/

func ==(inLeft: HttpResponse, inRight: HttpResponse) -> Bool {
    return inLeft.statusCode() == inRight.statusCode()
}

