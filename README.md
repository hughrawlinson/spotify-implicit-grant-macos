I decided to spend some time this weekend implementing the Spotify OAuth Implicit
Grant flow in a macOS app. I haven't spent a lot of time working with macOS
development in the past, so it was quite the voyage of discovery for me.

The Implicit Grant OAuth flow is the simplest flow to implement to facilitate
**user authorization** for your app. It doesn't return a refresh token, but
because the flow doesn't require the client secret, there's no serverside
component to this auth implementation.

## 1. Create a new project
Open up XCode, and open the 'New Project' wizard. Select 'Cocoa Application' as
your application type, and hit 'next'. Enter a product name, set your language
to 'Swift', and you'll be good to go!

## 2. Register a new Spotify Application

Follow Spotify's [Register Your Application]
(https://developer.spotify.com/web-api/tutorial/#registering-your-application)
guide to create a new set of Spotify app credentials.

## 3. Prepare some variables

In your `AppDelegate.swift`, you'll need to set up some variables to use when
constructing your authorize link. You can put these inside your AppDelegate
class.

```swift
let spotifyAccountsBaseUri = "https://accounts.spotify.com"
let spotifyAccountsAuthorizeUri = "\(spotifyAccountsBaseUri)/authorize"
let clientId = "[YOUR-CLIENT-ID]"
let uriSchemeBase = "my-awesome-app"
let redirectUri = "\(uriSchemeBase)://spotifyOauthCallback"
```

Lets unpack what's going on here. We're setting up a `spotifyAccountsBaseUri`,
which is the URI for the Spotify accounts service. We use it immediately in the
template string for `spotifyAccountsAuthorizeUri`, the base URI that you present
to your users to let them authorize your app to work with their Spotify account.

Next, we set up a client ID. This is available in the Spotify application you
set up in [Your Applications]
https://developer.spotify.com/my-applications/#!/applications). We'll use this
to present the authorization dialog for your app to your users.

We're going to use a URI Scheme to handle the redirection from the Spotify
accounts service back to your application once the user has authorized (or
decided not to authorize) your app. To handle this, we create a `uriSchemeBase`.
You can choose your own URI Scheme base, but it should be unique to your
application, and should be in [kebab-case]
(https://en.wikipedia.org/wiki/Letter_case#Special_case_styles), with all
letters lowercase. We'll modify your `App.plist` to tell macOS that your
application can handle your URI schema in a later step.

Finally, we register a `redirectUri`. This is the specific URI that your users
will be directed to once they've completed their steps of the implicit grant
flow. We'll listen for requests made to this URI later on in order to recieve
our access token. At this stage, you should take your full redirect uri (in this
case, `my-awesome-amm://spotifyOauthCallback`), and whitelist it in your
application settings page on [developer.spotify.com](//developer.spotify.com).
Remember to click save!

## 4. Present Spotify authorization dialog to user

When our application launches, we'll want to present the Spotify authorization
dialog to our user so that they can authorize our application, and we can start
calling the Spotify API. In the previous step, we created our
`spotifyAccountsAuthorizeUri`, which we'll now configure to authorize using the
client credentials flow, with your app's client id, and to redirect to the
correct place.

The accounts service takes our `redirect_uri` as a parameter - it has to be URL
encoded. In your AppDelegate template, you will see the stub function
`applicationDidFinishLaunching`. This method is called once the application has
finished launching - an excellent time to ask the user to authorize the app!
Inside that function, insert the following code:

```swift
let characterSet = NSMutableCharacterSet.alphanumeric()
characterSet.addCharacters(in: "-_.!~*'()")
let urlEncodedRedirectUri =   redirectUri.addingPercentEncoding(withAllowedCharacters: characterSet as CharacterSet)!
```

This takes the redirectUri we set up earlier and ensures that it's properly
encoded to work as a query parameter for our authorization URI.

Now we can construct the URI:

```swift
let authorizationUri = "\(spotifyAccountsAuthorizeUri)?response_type=token&client_id=\(clientId)&redirect_uri=\(urlEncodedRedirectUri)"
```

This line assigns a new constant `authorizationUri`, inserting a few query
parameters. The `response_type` parameter tells the Spotify accounts service
that we're following the _Implicit Grant_ flow as opposed to any of the other
supported authorization flows. We also provide the client ID of our application,
and the redirect_uri that we want the user to be redirected back to once they
complete the authorization dialog. If you were to print out the
`authorizationUri`, it would look something like this.

```
https://accounts.spotify.com/authorize?response_type=token&client_id=[YOUR-CLIENT-ID]&redirect_uri=my-awesome-app%3A%2F%2FspotifyOauthCallback
```

You can add scopes as a comma separated list of scope names (i.e.
`user-read-recently-played,user-modify-playback-state`) as a value of the
'scopes' query parameter, but for this example we don't need any extra special
scopes.

To present it to the user, you can evaluate the following expression:

```swift
if let url = URL(string: authorizationUri), NSWorkspace.shared().open(url) {
    print("Opened Spotify authorization dialog in user's default browser")
}
```

## 5. Recieving the request on your URI schema

At this point, if you run your app you should see your browser open to the
authorization uri, presenting an oauth dialog to your user (or asking them to
log in). If you get an error like "Invalid Client" or "Invalid Redirect URI",
make sure you've set your client id and redirect uris correctly at the top of
your file, and that you've definitely added **and saved** your redirect URI in
your Spotify Application Settings page.

But when you click 'Okay' on the Spotify Authorization Dialog, nothing happens!
This is because our app isn't yet listening to requests on your URI schema, so
it can't pick up the access token that the accounts service has tried to pass to
it.

To fix this, we'll code up an event handler that listens to requests on our URI
schema. We'll add two functions to our `AppDelegate` class.

```swift
func applicationWillFinishLaunching(_ notification: Notification) {
    let appleEventManager: NSAppleEventManager = NSAppleEventManager.shared()
    appleEventManager.setEventHandler(self, andSelector: #selector(handleGetURLEvent(event:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
}
```

`applicationWillFinishLaunching` will be called just before the application
finishes launching - this is when we need to register our listener. We tell the
Apple Event Manager to call our `handleGetURLEvent` function whenever it
recieves a request with a specific EventClass and EventID.

Now we'll implement our handler that `appleEventManager` will call.

```swift
// Set up a field on the AppDelegate class to store our accessToken
var accessToken: String? = nil

func handleGetURLEvent(event: NSAppleEventDescriptor) {
    guard let fullUrl = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
        return
    }

    guard let fragmentComponentsURL = URL(string: fullUrl) else {
        return
    }

    guard let fragmentComponentQueryItems = NSURLComponents(string: "?\((fragmentComponentsURL.fragment)!)")?.queryItems else {
        return
    }

    fragmentComponentQueryItems.forEach({ (item) in
        if item.name == "access_token" {
            accessToken = item.value
            print(accessToken)
        }
    })
}
```

We also need to tell macOS that our application can handle requests via our URI
Schema. To do this, we add a property to our app's `Info.plist`. You'll need to
add a property `URL Types`, which should give you an array with 1 item
(`Item 0`) containing a `URL Identifier`. To `Item 0`, you add a `URI Schemes`
property, which will give you another array with 1 item called `Item 0`. Set the
value of the inner `Item 0` to the value of your `uriSchemeBase` constant, set
at the top of your `AppDelegate`. In this example, it's `my-awesome-app`. Now
your app should be ready to handle requests using your URI Scheme!

![URL Scheme in Info.plist](https://gist.githubusercontent.com/hughrawlinson/b8c3db60fc3c1fb77ab74a1065c610c1/raw/e75674be57baef774465a8471eae7d3ff8fc2c74/URL_Scheme.png)

## 6. Use access token to query the Spotify API

Now that we've successfully completed the Implicit Grant OAuth flow, it's time
to use the access token we got to make a request to the Spotify API. Add this
method to your App Delegate. It makes a call to the API, converts the response
JSON String to a Swift object, and passes the value to a closure it recieves as
an argument.

```swift
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
```

Finally, we'll execute this function inside our redirect URI handler. The full
`handleGetURLEvent` should look like this:

```swift
func handleGetURLEvent(event: NSAppleEventDescriptor) {
    guard let fullUrl = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
        return
    }

    guard let fragmentComponentsURL = URL(string: fullUrl) else {
        return
    }

    guard let fragmentComponentQueryItems = NSURLComponents(string: "?\((fragmentComponentsURL.fragment)!)")?.queryItems else {
        return
    }

    fragmentComponentQueryItems.forEach({ (item) in
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
```

Now when you run the app and sign in, you should see this printed to your
console: `Congrats on implementing the Spotify Implicit Grant flow in your macOS
Application, Hugh Rawlinson!`, but with your Spotify Display Name, rather than
mine.

# Summary

Congrats on implementing the Implicit Grant OAuth flow in your macOS app! You've
done well! The entire `AppDelegate.swift` is available in this repo. If you need
any more help writing Spotify applications for macOS or any other platform,
please reach out to [@SpotifyPlatform](https://twitter.com/spotifyplatform) on
Twitter. Happy hacking!
