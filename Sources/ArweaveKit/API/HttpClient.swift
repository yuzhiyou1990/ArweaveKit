import Foundation
import PromiseKit

public struct HttpResponse {
    public let data: Data
    public let statusCode: Int
}
public struct HttpClient {

    static func request(_ target: Arweave.Request) -> Promise<HttpResponse>{
        let (promise, seal) = Promise<HttpResponse>.pending()
        var request = URLRequest(url: target.url)
        request.httpMethod = target.method
        request.httpBody = target.body
        request.allHTTPHeaderFields = target.headers
        DispatchQueue.global(qos: .userInitiated).async {
            let task  = URLSession.shared.dataTask(with: request) { data, response, error in
                if error != nil {
                    DispatchQueue.main.async {
                        seal.reject(error!)
                    }
                }else{
                    guard let _data = data, let _response = response as? HTTPURLResponse else {
                        DispatchQueue.main.async {
                            seal.reject(ArweaveApiError.unknown)
                        }
                        return
                    }
                    if case .transactionStatus = target.route {
                        
                    }else if _response.statusCode != 200{
                        let message = String(decoding: _data, as: UTF8.self)
                        DispatchQueue.main.async {
                            seal.reject(ArweaveApiError.responseError(
                                stateCode: _response.statusCode,
                                message: message
                            ))
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        seal.fulfill(.init(data: _data,statusCode:_response.statusCode))
                    }
                }
            }
            task.resume()
        }
        return promise
    }
}
