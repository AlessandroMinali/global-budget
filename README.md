Record personal payments at home and overseas with ease.

# Setup
`gem install sqlite3`

# Run
`ruby budget.rb`

```
Usage:
	b				- Inspect base currency
	b (\w{3})			- Set base curreny
	s				- Inspect avaiable conversion targets
	s (\w{3}\ ?\w{3}?)*		- Add conversion targets
	r				- Inspect all stored rates
	<VALUE> <CURRENCY> <NOTE>	- Add item:
					  <VALUE> required
					  <CURRENCY> optional, defaults to base
					  <DESCRIPTION> optional
	y				- Inspect year, used for totals
	y (\d{4})			- Set year used for totals
	t				- Calculate totals for year
	t (.+)				- Calculate totals for month in year
	exit
```