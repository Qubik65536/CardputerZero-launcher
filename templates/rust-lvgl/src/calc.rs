// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! `calc`, the tiny language behind the REPL demo: whole numbers, `+ - * / % ^`,
//! parentheses, variables (`x = 6 * 7`, `ans` is the last result) and the functions
//! `abs`, `min` and `max`. Pure logic, no screen: `cargo test` checks it.

use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq, Eq)]
enum Token {
    Number(i64),
    Name(String),
    Symbol(char),
}

fn describe(token: &Token) -> String {
    match token {
        Token::Number(value) => value.to_string(),
        Token::Name(name) => name.clone(),
        Token::Symbol(symbol) => symbol.to_string(),
    }
}

fn tokenize(line: &str) -> Result<Vec<Token>, String> {
    let characters: Vec<char> = line.chars().collect();
    let mut tokens = Vec::new();
    let mut index = 0;
    while index < characters.len() {
        let character = characters[index];
        let start = index;
        if character.is_whitespace() {
            index += 1;
        } else if character.is_ascii_digit() {
            while index < characters.len() && characters[index].is_ascii_digit() {
                index += 1;
            }
            let digits: String = characters[start..index].iter().collect();
            tokens.push(Token::Number(digits.parse().map_err(|_| "number too large".to_string())?));
        } else if character.is_ascii_alphabetic() || character == '_' {
            while index < characters.len() && (characters[index].is_ascii_alphanumeric() || characters[index] == '_') {
                index += 1;
            }
            tokens.push(Token::Name(characters[start..index].iter().collect()));
        } else if "+-*/%^()=,".contains(character) {
            tokens.push(Token::Symbol(character));
            index += 1;
        } else {
            return Err(format!("unexpected '{character}'"));
        }
    }
    Ok(tokens)
}

const OVERFLOW: &str = "overflow";

fn power(base: i64, exponent: i64) -> Result<i64, String> {
    if exponent < 0 {
        return Err("negative exponent".to_string());
    }
    let exponent = u32::try_from(exponent).map_err(|_| OVERFLOW.to_string())?;
    base.checked_pow(exponent).ok_or_else(|| OVERFLOW.to_string())
}

fn call(name: &str, arguments: &[i64]) -> Result<i64, String> {
    match (name, arguments) {
        ("abs", [value]) => value.checked_abs().ok_or_else(|| OVERFLOW.to_string()),
        ("min", [first, second]) => Ok(*first.min(second)),
        ("max", [first, second]) => Ok(*first.max(second)),
        ("abs", _) => Err("abs takes 1 argument".to_string()),
        ("min" | "max", _) => Err(format!("{name} takes 2 arguments")),
        _ => Err(format!("unknown function '{name}'")),
    }
}

/// Recursive-descent evaluator. Grammar, loosest binding first:
///   expression = term (("+" | "-") term)*
///   term       = unary (("*" | "/" | "%") unary)*
///   unary      = "-" unary | power
///   power      = atom ("^" unary)?          (so 2^3^2 = 2^9 and -2^2 = -4)
///   atom       = number | name | name "(" arguments ")" | "(" expression ")"
struct Parser<'a> {
    tokens: &'a [Token],
    position: usize,
    variables: &'a BTreeMap<String, i64>,
}

impl Parser<'_> {
    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.position)
    }

    fn next_is(&self, symbol: char) -> bool {
        self.peek() == Some(&Token::Symbol(symbol))
    }

    fn unexpected(&self) -> String {
        match self.peek() {
            Some(token) => format!("unexpected '{}'", describe(token)),
            None => "incomplete expression".to_string(),
        }
    }

    fn expect(&mut self, symbol: char) -> Result<(), String> {
        if !self.next_is(symbol) {
            return Err(format!("expected '{symbol}'"));
        }
        self.position += 1;
        Ok(())
    }

    fn arguments(&mut self) -> Result<Vec<i64>, String> {
        let mut values = Vec::new();
        if self.next_is(')') {
            return Ok(values);
        }
        values.push(self.expression()?);
        while self.next_is(',') {
            self.position += 1;
            values.push(self.expression()?);
        }
        Ok(values)
    }

    fn atom(&mut self) -> Result<i64, String> {
        match self.peek().cloned() {
            Some(Token::Number(value)) => {
                self.position += 1;
                Ok(value)
            }
            Some(Token::Name(name)) => {
                self.position += 1;
                if self.next_is('(') {
                    self.position += 1;
                    let arguments = self.arguments()?;
                    self.expect(')')?;
                    return call(&name, &arguments);
                }
                self.variables.get(&name).copied().ok_or_else(|| format!("unknown name '{name}'"))
            }
            Some(Token::Symbol('(')) => {
                self.position += 1;
                let value = self.expression()?;
                self.expect(')')?;
                Ok(value)
            }
            _ => Err(self.unexpected()),
        }
    }

    fn power(&mut self) -> Result<i64, String> {
        let base = self.atom()?;
        if !self.next_is('^') {
            return Ok(base);
        }
        self.position += 1;
        let exponent = self.unary()?;
        power(base, exponent)
    }

    fn unary(&mut self) -> Result<i64, String> {
        if self.next_is('-') {
            self.position += 1;
            return self.unary()?.checked_neg().ok_or_else(|| OVERFLOW.to_string());
        }
        self.power()
    }

    fn term(&mut self) -> Result<i64, String> {
        let mut value = self.unary()?;
        while let Some(Token::Symbol(operator @ ('*' | '/' | '%'))) = self.peek().cloned() {
            self.position += 1;
            let right = self.unary()?;
            if operator != '*' && right == 0 {
                return Err("division by zero".to_string());
            }
            value = match operator {
                '*' => value.checked_mul(right),
                '/' => value.checked_div(right),
                _ => value.checked_rem(right),
            }
            .ok_or_else(|| OVERFLOW.to_string())?;
        }
        Ok(value)
    }

    fn expression(&mut self) -> Result<i64, String> {
        let mut value = self.term()?;
        while let Some(Token::Symbol(operator @ ('+' | '-'))) = self.peek().cloned() {
            self.position += 1;
            let right = self.term()?;
            value = if operator == '+' { value.checked_add(right) } else { value.checked_sub(right) }
                .ok_or_else(|| OVERFLOW.to_string())?;
        }
        Ok(value)
    }
}

const FUNCTIONS: [&str; 3] = ["abs", "min", "max"];

/// The interpreter: variables live as long as it does.
#[derive(Default)]
pub struct Calculator {
    variables: BTreeMap<String, i64>,
}

impl Calculator {
    pub fn new() -> Calculator {
        Calculator::default()
    }

    /// Run one line: an expression (`1 + 2`) or an assignment (`x = 1 + 2`).
    /// Returns the text to show, `3` or `x = 3`.
    pub fn run(&mut self, line: &str) -> Result<String, String> {
        let tokens = tokenize(line)?;
        let target = match tokens.as_slice() {
            [Token::Name(name), Token::Symbol('='), ..] => Some(name.clone()),
            _ => None,
        };
        if let Some(name) = &target {
            if FUNCTIONS.contains(&name.as_str()) {
                return Err(format!("{name} is a function"));
            }
        }
        let skip = if target.is_some() { 2 } else { 0 };
        let mut parser = Parser { tokens: &tokens[skip..], position: 0, variables: &self.variables };
        let value = parser.expression()?;
        if parser.peek().is_some() {
            return Err(parser.unexpected());
        }
        self.variables.insert("ans".to_string(), value);
        match target {
            Some(name) => {
                self.variables.insert(name.clone(), value);
                Ok(format!("{name} = {value}"))
            }
            None => Ok(value.to_string()),
        }
    }

    /// Every variable and its value, in name order.
    pub fn variables(&self) -> impl Iterator<Item = (&str, i64)> {
        self.variables.iter().map(|(name, value)| (name.as_str(), *value))
    }
}

#[cfg(test)]
mod tests {
    use super::Calculator;

    fn run(line: &str) -> Result<String, String> {
        Calculator::new().run(line)
    }

    #[test]
    fn arithmetic_follows_the_usual_rules() {
        assert_eq!(run("1 + 2 * 3"), Ok("7".into()));
        assert_eq!(run("(1 + 2) * 3"), Ok("9".into()));
        assert_eq!(run("7 / 2"), Ok("3".into()));
        assert_eq!(run("-7 / 2"), Ok("-3".into()));
        assert_eq!(run("-7 % 3"), Ok("-1".into()));
        assert_eq!(run("2 ^ 3 ^ 2"), Ok("512".into()));
        assert_eq!(run("-2 ^ 2"), Ok("-4".into()));
        assert_eq!(run("10 - 4 - 3"), Ok("3".into()));
        assert_eq!(run("max(3, abs(-8)) + min(1, 2)"), Ok("9".into()));
    }

    #[test]
    fn variables_and_ans_persist() {
        let mut calculator = Calculator::new();
        assert_eq!(calculator.run("x = 6 * 7"), Ok("x = 42".into()));
        assert_eq!(calculator.run("x + 1"), Ok("43".into()));
        assert_eq!(calculator.run("ans * 2"), Ok("86".into()));
        let names: Vec<_> = calculator.variables().collect();
        assert_eq!(names, vec![("ans", 86), ("x", 42)]);
    }

    #[test]
    fn mistakes_are_explained() {
        assert_eq!(run("1 / 0"), Err("division by zero".into()));
        assert_eq!(run("y + 1"), Err("unknown name 'y'".into()));
        assert_eq!(run("(1 + 2"), Err("expected ')'".into()));
        assert_eq!(run("1 +"), Err("incomplete expression".into()));
        assert_eq!(run("1 2"), Err("unexpected '2'".into()));
        assert_eq!(run("2 $ 3"), Err("unexpected '$'".into()));
        assert_eq!(run("2 ^ -1"), Err("negative exponent".into()));
        assert_eq!(run("2 ^ 64"), Err("overflow".into()));
        assert_eq!(run("abs(1, 2)"), Err("abs takes 1 argument".into()));
        assert_eq!(run("sqrt(4)"), Err("unknown function 'sqrt'".into()));
        assert_eq!(run("max = 3"), Err("max is a function".into()));
        assert_eq!(run("99999999999999999999"), Err("number too large".into()));
    }
}
