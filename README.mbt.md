---
moonbit:
  deps:
    ryota0624/mustache: 
      path: "./"
  backend:
    js
---

# ryota0624/mustache

https://github.com/alexkappa/mustache
を参考に実装されたMoonbit用のMustache実装です。

元の実装同様いくつかのspecを満たしていません。

```mbt
test {
	let template = "{{#users}}{{name}}: {{age}}\n{{/users}}"
	let data = Json::object(
		{
			"users": [
				{"name": "Alice", "age": 30},
				{"name": "Bob", "age": 25}
			]
		}
	)
  
	assert_eq(
		@lib.parse(template, data),
		"Alice: 30\nBob: 25\n"
	)
}

```
