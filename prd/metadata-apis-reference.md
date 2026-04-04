# Book Metadata APIs Reference Guide

## Best Open/Free Options for Your Audiobook App

### 1. **Open Library** ⭐ Recommended Primary
**Status:** Free, no API key required  
**Coverage:** 30M+ books (via Internet Archive)  
**Best for:** ISBN lookups, fallback searches

**Data available:**
- Title, author, cover image, publish date, publisher
- ISBN-10, ISBN-13, LCCN, OCLC
- Description, subjects, page count
- Goodreads/LibraryThing cross-references

**Endpoints:**
```bash
# By ISBN
curl 'https://openlibrary.org/api/books?bibkeys=ISBN:9780134685991&jscmd=data&format=json'

# By title/author
curl 'https://openlibrary.org/search.json?title=Dune&author=Frank+Herbert&limit=10'

# Direct ISBN
curl 'https://openlibrary.org/isbn/9780134685991.json'
```

**Pros:**
- Completely free, no rate limits documented
- Excellent ISBN coverage (matches 90%+ of books)
- Good for bulk imports
- Covers API returns 3 sizes (small, medium, large)
- No authentication needed

**Cons:**
- Cover images sometimes missing (copyright reasons)
- Description field often incomplete
- Less metadata than commercial sources

**Rate Limit:** Not documented (safe for reasonable usage)

---

### 2. **Google Books API** ⭐ Recommended Secondary
**Status:** Free tier available (100 queries/day), API key required  
**Coverage:** 40M+ books  
**Best for:** Descriptions, preview links, comprehensive metadata

**Data available:**
- Title, author, description (preview text)
- Cover image, publish date, publisher
- ISBN variants, page count, language
- Preview links to Google Books

**Endpoints:**
```bash
# By ISBN
curl 'https://www.googleapis.com/books/v1/volumes?q=isbn:9780134685991&key=YOUR_KEY'

# By title/author
curl 'https://www.googleapis.com/books/v1/volumes?q=Dune+Frank+Herbert&key=YOUR_KEY'
```

**Pros:**
- Good quality descriptions
- Reliably returns cover images
- Free tier adequate for most apps
- Easy to set up (Google Cloud Console)

**Cons:**
- Requires API key setup
- Rate limited on free tier (100/day)
- Preview URLs may not resolve for all books

**Rate Limit:** 100 queries/day (free) → upgrade for more  
**Setup:** Get key from [Google Cloud Console](https://console.cloud.google.com/)

---

### 3. **Internet Archive API**
**Status:** Free, no key required  
**Coverage:** 20M+ digitized books + 500K+ recordings  
**Best for:** Descriptions, public domain, audiobooks

**Data available:**
- Title, author, description
- Cover/metadata, publish date
- Audiobook formats and narrators
- Full-text search within books

**Endpoints:**
```bash
curl 'https://archive.org/advancedsearch.php?q=isbn:9780134685991&output=json'
curl 'https://archive.org/metadata/{identifier}'
```

**Pros:**
- Great for public domain audiobooks
- Excellent for Project Gutenberg books
- No rate limiting
- Includes narrator info for audiobooks

**Cons:**
- Identifier-based (need to find correct ID first)
- Less complete coverage of recent books
- Response format less standardized

---

### 4. **OCLC Classify** (Utility)
**Status:** Free, no key required  
**Coverage:** 586M+ bibliographic records  
**Best for:** ISBN validation, cross-reference identifiers

**Data available:**
- ISBN verification/crosswalk
- Dewey Decimal Classification
- Library of Congress Classification
- Related editions

**Endpoints:**
```bash
curl 'https://classify.oclc.org/classify2/Classify?isbn=978-0-465-05373-5&summary=true'
```

**Pros:**
- Authoritative ISBN validation
- Helps find related editions
- Free and reliable

**Cons:**
- Limited metadata (mainly classification)
- Better as supplement than primary source

---

## ⚠️ NOT RECOMMENDED

### Goodreads API
- **Status:** No longer issuing new API keys (as of Dec 2020)
- **Future:** Plans to retire API entirely
- **Alternative:** Community projects like [LazyLibrarian](https://lazylibrarian.gitlab.io/) provide fallback keys, but not reliable long-term
- Use scraping-based approaches (like abs-tract project) if you want Goodreads data

### ISBNdb
- **Status:** Paid only ($10-300/month)
- **Not suitable** for a free/open app

### Amazon Product API
- **Status:** Requires Amazon Associates affiliation
- Covers are highest quality but registration is restrictive
- Better as optional premium feature

---

## Recommended Implementation Strategy

### **Fallback Chain** (use in order):
1. **Open Library** (primary)
   - Query by ISBN first
   - Fallback to title+author
   - Get: title, author, cover, publish date, description

2. **Google Books API** (secondary)
   - If Open Library returns partial metadata
   - Fill gaps in description and cover
   - Get better preview links

3. **Internet Archive** (tertiary)
   - For public domain/special collections
   - Audiobook-specific metadata (narrators)
   - Extended descriptions

### **Matching & Deduplication:**

```javascript
// Confidence scoring algorithm
function scoreMatch(result, query) {
  let score = 0;
  
  // ISBN match (most reliable)
  if (result.isbn === query.isbn) return 100;
  
  // Title + Author fuzzy match
  const titleMatch = fuzzyScore(result.title, query.title);
  const authorMatch = fuzzyScore(result.author, query.author);
  score = (titleMatch * 0.6 + authorMatch * 0.4) * 100;
  
  // Year match (tiebreaker)
  if (result.publishYear === query.publishYear) score += 5;
  
  return Math.min(score, 99);
}

// Return top 5 by score
results.sort((a, b) => scoreMatch(b, query) - scoreMatch(a, query));
return results.slice(0, 5);
```

### **Handling Multiple Matches:**

**Show user a selection UI with:**
- Thumbnail covers (side-by-side)
- Title, author, narrator (if audiobook)
- Publisher, edition year
- Confidence score
- Differentiators (e.g., "Audiobook 2020" vs. "eBook 2018")

**Example:**
```
[Thumbnail]              [Thumbnail]              [Thumbnail]
The Great Gatsby         The Great Gatsby         The Great Gatsby
by F. Scott Fitzgerald   by F. Scott Fitzgerald   by F. Scott Fitzgerald
Audiobook 2024           eBook 2023               eBook 2013
Narrated by Jake Zoom    Kindle Edition           Penguin Classics
⭐ 98% match             ⭐ 85% match             ⭐ 72% match
```

---

## Implementation Checklist

- [ ] Set up Open Library integration (no setup needed)
- [ ] Generate Google Books API key (free tier)
- [ ] Implement fuzzy matching for title/author
- [ ] Build match selection UI with confidence scores
- [ ] Cache metadata for 30+ days
- [ ] Implement exponential backoff for rate limits
- [ ] Add "Manual Entry" fallback
- [ ] Test with 1000+ book imports
- [ ] Monitor API response times and errors

---

## Code Examples

### Basic Open Library Lookup (JavaScript)
```javascript
async function enrichMetadataOpenLibrary(isbn) {
  const url = `https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&jscmd=data&format=json`;
  const response = await fetch(url);
  const data = await response.json();
  
  const key = `ISBN:${isbn}`;
  if (data[key]) {
    return {
      title: data[key].title,
      author: data[key].authors?.[0]?.name,
      cover: data[key].cover?.large,
      publishDate: data[key].publish_date,
      publisher: data[key].publishers?.[0]?.name,
      description: data[key].description
    };
  }
  return null;
}
```

### Fallback Chain (JavaScript)
```javascript
async function enrichMetadata(book) {
  // Try Open Library first
  let metadata = await enrichMetadataOpenLibrary(book.isbn);
  if (metadata) return metadata;
  
  // Fallback to Google Books
  metadata = await enrichMetadataGoogleBooks(book.isbn);
  if (metadata) return metadata;
  
  // Fallback to Internet Archive
  metadata = await enrichMetadataInternetArchive(book.title, book.author);
  return metadata || null;
}
```

---

## Cost Analysis

| Service | Cost | Query Limit | Best For |
|---------|------|-------------|----------|
| Open Library | Free | Unlimited | Primary ISBN lookups |
| Google Books | Free | 100/day | Secondary + descriptions |
| Internet Archive | Free | Unlimited | Audiobooks, public domain |
| OCLC Classify | Free | Unlimited | ISBN validation |
| ISBNdb | $10-300/mo | Tier-based | Large-scale commercial apps |
| Amazon PA API | Free | ~1/sec | High-quality covers (affiliate only) |

**Recommendation for your app:** Open Library + Google Books = **$0/month** ✅

---

## Handling Match Ambiguity

**When >1 result returned:**

1. **Show top 3-5 matches** (ranked by confidence)
2. **User selects** the correct edition
3. **Store selection** (for future reference)
4. **Allow manual override** (edit any field)
5. **Save as template** for similar books (e.g., "all by this author → narrator X")

**Confidence Threshold:**
- <40%: Show to user as "possible match" 
- 40-80%: Show as "likely match"
- >80%: Auto-select (user can override)

---

## Real-World Example: AudiobookShelf

AudiobookShelf (open-source audiobook server) uses:
- **Goodreads** (metadata, descriptions) + **Kindle/Amazon** (high-quality covers)
- Falls back to local file metadata (ID3 tags for MP3s)

Since Goodreads API is deprecated, the community is migrating to:
- Open Library (primary)
- Internet Archive (audiobooks)
- Manual user submission for missing data

