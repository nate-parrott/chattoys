import Foundation

/*
 {'hits': [{'description': 'Fresh pasta counter in Park Slope, Brooklyn. Eat pasta, drink wine, cool down with ice cream.', 'snippets': ["Skip to main content\nReservations\nEvents\nFind Us\nPasta Louise Cafe on 8th St.\nPasta Louise Restaurant on 12th St.\nMenus\nJobs\nScholarship\nAbout\nGift Cards\nCatering\nOrder Online\nToggle Navigation\nReservations\nEvents\nFind Us\nPasta Louise Cafe on 8th St.\nPasta Louise Restaurant on 12th St.\nMenus\nJobs\nScholarship\nAbout\nGift Cards\nCatering\nNewsletter\nContact\nPress\nGift Cards\nOrder Online\nEmail Signup\nFacebook\nInstagram\npowered by BentoBox\nHome\nMain content starts here, tab to start navigating\nLET'S EAT TOGETHER THIS HOLIDAY SEASON\nORDER ONLINE\nSlide 1 of 5\nSlide 2 of 5\nSlide 3 of 5\nSlide 4 of 5\nSlide 5 of 5\nhero gallery paused, press to play images slides\nPlaying hero gallery, press to pause images slides\nWelcome to Pasta Louise\nWe can't wait to meet you!\nmenu\nPasta Kits + Catering\npasta rose scholarship\nshop pasta louise\nleave this field blank\nEmail Signup\nFirst Name\n- Required\nLast Name\n- Required\nEmail\n- Required\nSubmit\nPlease check errors in the form above", 'Submit\nPlease check errors in the form above\nThank you for signing up for email updates!\nClose\nReservations\nLocation\n- Required\nLocation\nPasta Louise | Italian Restaurant in Park Slope, Brooklyn\nPasta Louise Restaurant on 12th St.\nNumber of People\n- Optional\nNumber of People\n1 Person\n2 People\n3 People\n4 People\n5 People\n6 People\n7 People\n8+ People\nDate\n- Required\nTime\n- Optional\nTime\n11:00 PM\n10:30 PM\n10:00 PM\n9:30 PM\n9:00 PM\n8:30 PM\n8:00 PM\n7:30 PM\n7:00 PM\n6:30 PM\n6:00 PM\n5:30 PM\n5:00 PM\n4:30 PM\n4:00 PM\n3:30 PM\n3:00 PM\n2:30 PM\n2:00 PM\n1:30 PM\n1:00 PM\n12:30 PM\n12:00 PM\n11:30 AM\n11:00 AM\n10:30 AM\n10:00 AM\n9:30 AM\n9:00 AM\n8:30 AM\n8:00 AM\n7:30 AM\n7:00 AM\nFind A Table\nPlease check errors in the form above\nThanks!'], 'title': 'Pasta Louise | Italian Restaurant in Park Slope, Brooklyn', 'url': 'https://www.pastalouise.com/'}, {'description': 'Discover restaurants to love in your city and beyond. Get the latest restaurant intel and explore Resy’s curated guides to find the right spot for any occasion. Book your table now through the Resy iOS app or Resy.com.', 'snippets': ["{{'titles.skip_to_main' | translate}}\nMain Content"], 'title': 'Book Your Pasta Louise Reservation Now on ...', 'url': 'https://resy.com/cities/ny/pasta-louise'}, {'description': 'Pasta Louise Cafe, 803 8th Ave, Brooklyn, NY 11215, Mon - Closed, Tue - 8:00 am - 9:00 pm, Wed - 8:00 am - 9:00 pm, Thu - 8:00 am - 9:00 pm, Fri - 8:00 am - 9:00 pm, Sat - 9:00 am - 9:00 pm, Sun - 9:00 am - 9:00 pm', 'snippets': ['Got a question about Pasta Louise Cafe? Ask the Yelp community!'], 'title': 'PASTA LOU
 */

struct YouResponse: Codable {
    struct Hit: Codable {
        var description: String?
        var snippets: [String]
        var title: String
        var url: String

        var webSearchResult: WebSearchResult? {
            guard let urlParsed = URL(string: url) else { return nil }
            return WebSearchResult(url: urlParsed, title: title, snippet: description)
        }

        var asWebContextPage: WebContext.Page? {
            guard let webSearchResult else { return nil }
            return .init(searchResult: webSearchResult, markdown: snippets.joined(separator: "\n\n"))
        }
    }
    var hits: [Hit]
}

/*
    headers = {"X-API-Key": YOUR_API_KEY}
    params = {"query": query}
    return requests.get(
        f"https://api.ydc-index.io/search",
        params=params,
        headers=headers,
    ).json()
*/

extension WebContext {
    public static func fetchViaYoudotcom(query: String, key: String, charLimit: Int) async throws -> WebContext {
        var urlComps = URLComponents(string: "https://api.ydc-index.io/search")!
        urlComps.queryItems = [URLQueryItem(name: "query", value: query)]
        var urlReq = URLRequest(url: urlComps.url!)
        urlReq.httpMethod = "GET"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue(key, forHTTPHeaderField: "X-API-Key")
        let (data, _) = try await URLSession.shared.data(for: urlReq)
        print("Response: \n\(String(data: data, encoding: .utf8) ?? "None")")
        let response = try JSONDecoder().decode(YouResponse.self, from: data)
        return WebContext(pages: response.hits.compactMap(\.asWebContextPage), urlMode: .truncate(100), query: query)
            .trimToFit(charLimit: charLimit)
    }

    public static func fetchViaYoudotcomWithGoogleAdditions(query: String, key: String, charLimit: Int) async throws -> (WebContext, [WebSearchResult]) {
        async let you_ = fetchViaYoudotcom(query: query, key: key, charLimit: charLimit)
        async let google_ = GoogleSearchEngine().search(query: query)

        var final = try await you_
        let google = try await google_

        if let googleHTML = google.html {
            try? final.pages.insert(.fromHTML(result: WebSearchResult(url: .googleSearch(query), title: "Search results for '\(query)'", snippet: nil), html: googleHTML, urlMode: .truncate(100)), at: 0)
        }

        return (final, google.results)
    }
}
