//
//  AppDelegate.swift
//  implicit-grant
//
//  Created by Hugh Rawlinson on 2017-05-21.
//  Copyright © 2017 Hugh Rawlinson. All rights reserved.
//

import Cocoa

let spotifyAccountsBaseUri = "https://accounts.spotify.com"
let spotifyAccountsAuthorizeUri = "\(spotifyAccountsBaseUri)/authorize"
let clientId = "[YOUR-CLIENT-ID]"
let uriSchemeBase = "my-awesome-app"
let redirectUri = "\(uriSchemeBase)://spotifyOauthCallback"

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var accessToken: String? = nil
    
    func handleGetURLEvent(event: NSAppleEventDescriptor) {
        if let fullUrl = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue {
            if let fragmentComponents = URL(string: fullUrl) {
                NSURLComponents(string: "?\((fragmentComponents.fragment)!)")?.queryItems?.forEach({ (item) in
                    if item.name == "access_token" {
                        accessToken = item.value
                        getSpotifyUserDetails(dataHandler: { (details) in
                            if details["display_name"] != nil {
                                print("Congrats on implementing the Spotify Implicit Grant flow in your macOS Application, \(details["display_name"]!)!")
                            }
                        })
                    }
                })
            }
        }
    }
    
    func getSpotifyUserDetails(dataHandler: @escaping ([String: Any]) -> Void) {
        if (accessToken != nil) {
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
            request.httpMethod = "GET"
            request.addValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data, error == nil else {
                    print("error=\(String(describing: error))")
                    return
                }
                
                if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 200 {
                    print("statusCode should be 200, but is \(httpStatus.statusCode)")
                    print("response = \(String(describing: response))")
                }
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let dictionary = json as? [String: Any] {
                        dataHandler(dictionary)
                    }
                }
            }
            task.resume()
        }
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        let appleEventManager: NSAppleEventManager = NSAppleEventManager.shared()
        appleEventManager.setEventHandler(self, andSelector: #selector(handleGetURLEvent(event:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let characterSet = NSMutableCharacterSet.alphanumeric()
        characterSet.addCharacters(in: "-_.!~*'()")
        let urlEncodedRedirectUri =   redirectUri.addingPercentEncoding(withAllowedCharacters: characterSet as CharacterSet)!
        
        let authorizationUri = "\(spotifyAccountsAuthorizeUri)?response_type=token&client_id=\(clientId)&redirect_uri=\(urlEncodedRedirectUri)"

        if let url = URL(string: authorizationUri), NSWorkspace.shared().open(url) {}
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

