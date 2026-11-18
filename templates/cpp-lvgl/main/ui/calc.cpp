/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "calc.hpp"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <limits>
#include <vector>

namespace {

// Thrown inside the interpreter; Calculator::run turns it into an error result.
struct CalcError
{
    std::string message;
};

const char *const kOverflow = "overflow";

struct Token
{
    enum class Kind { Number, Name, Symbol };
    Kind kind;
    int64_t number = 0;
    std::string name;
    char symbol = 0;
};

bool is_symbol(const Token *token, char symbol)
{
    return token && token->kind == Token::Kind::Symbol && token->symbol == symbol;
}

std::string describe(const Token &token)
{
    switch (token.kind) {
    case Token::Kind::Number: return std::to_string(token.number);
    case Token::Kind::Name: return token.name;
    case Token::Kind::Symbol: return std::string(1, token.symbol);
    }
    return {};
}

// Length in bytes of the UTF-8 character starting with `lead`.
size_t utf8_length(unsigned char lead)
{
    if (lead >= 0xF0) return 4;
    if (lead >= 0xE0) return 3;
    if (lead >= 0xC0) return 2;
    return 1;
}

bool is_name_start(char character)
{
    return std::isalpha(static_cast<unsigned char>(character)) || character == '_';
}

bool is_name_part(char character)
{
    return std::isalnum(static_cast<unsigned char>(character)) || character == '_';
}

int64_t parse_number(const std::string &digits)
{
    int64_t value = 0;
    for (char digit : digits) {
        if (__builtin_mul_overflow(value, 10, &value) || __builtin_add_overflow(value, digit - '0', &value))
            throw CalcError{"number too large"};
    }
    return value;
}

std::vector<Token> tokenize(const std::string &line)
{
    std::vector<Token> tokens;
    size_t index = 0;
    while (index < line.size()) {
        const char character = line[index];
        const size_t start = index;
        const unsigned char byte = static_cast<unsigned char>(character);
        if (byte < 0x80 && std::isspace(byte)) {
            ++index;
        } else if (byte < 0x80 && std::isdigit(byte)) {
            while (index < line.size() && std::isdigit(static_cast<unsigned char>(line[index]))) ++index;
            tokens.push_back({Token::Kind::Number, parse_number(line.substr(start, index - start)), {}, 0});
        } else if (byte < 0x80 && is_name_start(character)) {
            while (index < line.size() && is_name_part(line[index])) ++index;
            tokens.push_back({Token::Kind::Name, 0, line.substr(start, index - start), 0});
        } else if (byte < 0x80 && std::strchr("+-*/%^()=,", character)) {
            tokens.push_back({Token::Kind::Symbol, 0, {}, character});
            ++index;
        } else {
            throw CalcError{"unexpected '" + line.substr(start, utf8_length(byte)) + "'"};
        }
    }
    return tokens;
}

// i64 arithmetic that reports overflow instead of wrapping, like Rust's checked_*.
int64_t checked_add(int64_t left, int64_t right)
{
    int64_t result = 0;
    if (__builtin_add_overflow(left, right, &result)) throw CalcError{kOverflow};
    return result;
}

int64_t checked_sub(int64_t left, int64_t right)
{
    int64_t result = 0;
    if (__builtin_sub_overflow(left, right, &result)) throw CalcError{kOverflow};
    return result;
}

int64_t checked_mul(int64_t left, int64_t right)
{
    int64_t result = 0;
    if (__builtin_mul_overflow(left, right, &result)) throw CalcError{kOverflow};
    return result;
}

// Same steps as Rust's i64::checked_pow: square-and-multiply, failing on overflow.
int64_t power(int64_t base, int64_t exponent)
{
    if (exponent < 0) throw CalcError{"negative exponent"};
    if (exponent > std::numeric_limits<uint32_t>::max()) throw CalcError{kOverflow};
    if (exponent == 0) return 1;
    int64_t result = 1;
    while (exponent > 1) {
        if (exponent & 1) result = checked_mul(result, base);
        exponent /= 2;
        base = checked_mul(base, base);
    }
    return checked_mul(result, base);
}

int64_t call(const std::string &name, const std::vector<int64_t> &arguments)
{
    const bool known = name == "abs" || name == "min" || name == "max";
    if (!known) throw CalcError{"unknown function '" + name + "'"};
    if (name == "abs") {
        if (arguments.size() != 1) throw CalcError{"abs takes 1 argument"};
        if (arguments[0] == std::numeric_limits<int64_t>::min()) throw CalcError{kOverflow};
        return arguments[0] < 0 ? -arguments[0] : arguments[0];
    }
    if (arguments.size() != 2) throw CalcError{name + " takes 2 arguments"};
    return name == "min" ? std::min(arguments[0], arguments[1]) : std::max(arguments[0], arguments[1]);
}

// Recursive-descent evaluator. Grammar, loosest binding first:
//   expression = term (("+" | "-") term)*
//   term       = unary (("*" | "/" | "%") unary)*
//   unary      = "-" unary | power
//   power      = atom ("^" unary)?          (so 2^3^2 = 2^9 and -2^2 = -4)
//   atom       = number | name | name "(" arguments ")" | "(" expression ")"
struct Parser
{
    const std::vector<Token> &tokens;
    size_t position;
    const std::map<std::string, int64_t> &variables;

    const Token *peek() const
    {
        return position < tokens.size() ? &tokens[position] : nullptr;
    }

    bool next_is(char symbol) const
    {
        return is_symbol(peek(), symbol);
    }

    std::string unexpected() const
    {
        const Token *token = peek();
        return token ? "unexpected '" + describe(*token) + "'" : "incomplete expression";
    }

    void expect(char symbol)
    {
        if (!next_is(symbol)) throw CalcError{std::string("expected '") + symbol + "'"};
        ++position;
    }

    int64_t expression();

    std::vector<int64_t> arguments()
    {
        std::vector<int64_t> values;
        if (next_is(')')) return values;
        values.push_back(expression());
        while (next_is(',')) {
            ++position;
            values.push_back(expression());
        }
        return values;
    }

    int64_t atom()
    {
        const Token *token = peek();
        if (token && token->kind == Token::Kind::Number) {
            ++position;
            return token->number;
        }
        if (token && token->kind == Token::Kind::Name) {
            ++position;
            if (next_is('(')) {
                ++position;
                const std::vector<int64_t> values = arguments();
                expect(')');
                return call(token->name, values);
            }
            const auto found = variables.find(token->name);
            if (found == variables.end()) throw CalcError{"unknown name '" + token->name + "'"};
            return found->second;
        }
        if (is_symbol(token, '(')) {
            ++position;
            const int64_t value = expression();
            expect(')');
            return value;
        }
        throw CalcError{unexpected()};
    }

    int64_t unary();

    int64_t power_expression()
    {
        const int64_t base = atom();
        if (!next_is('^')) return base;
        ++position;
        const int64_t exponent = unary();
        return power(base, exponent);
    }

    int64_t term()
    {
        int64_t value = unary();
        while (is_symbol(peek(), '*') || is_symbol(peek(), '/') || is_symbol(peek(), '%')) {
            const char op = peek()->symbol;
            ++position;
            const int64_t right = unary();
            if (op == '*') {
                value = checked_mul(value, right);
                continue;
            }
            if (right == 0) throw CalcError{"division by zero"};
            if (value == std::numeric_limits<int64_t>::min() && right == -1) throw CalcError{kOverflow};
            value = op == '/' ? value / right : value % right;
        }
        return value;
    }
};

int64_t Parser::unary()
{
    if (next_is('-')) {
        ++position;
        const int64_t value = unary();
        if (value == std::numeric_limits<int64_t>::min()) throw CalcError{kOverflow};
        return -value;
    }
    return power_expression();
}

int64_t Parser::expression()
{
    int64_t value = term();
    while (is_symbol(peek(), '+') || is_symbol(peek(), '-')) {
        const char op = peek()->symbol;
        ++position;
        const int64_t right = term();
        value = op == '+' ? checked_add(value, right) : checked_sub(value, right);
    }
    return value;
}

} // namespace

CalcResult Calculator::run(const std::string &line)
{
    try {
        const std::vector<Token> tokens = tokenize(line);
        std::string target;
        if (tokens.size() >= 2 && tokens[0].kind == Token::Kind::Name && is_symbol(&tokens[1], '='))
            target = tokens[0].name;
        if (target == "abs" || target == "min" || target == "max") return {false, target + " is a function"};

        Parser parser{tokens, target.empty() ? size_t{0} : size_t{2}, variables_};
        const int64_t value = parser.expression();
        if (parser.peek()) return {false, parser.unexpected()};
        variables_["ans"] = value;
        if (target.empty()) return {true, std::to_string(value)};
        variables_[target] = value;
        return {true, target + " = " + std::to_string(value)};
    } catch (const CalcError &error) {
        return {false, error.message};
    }
}
