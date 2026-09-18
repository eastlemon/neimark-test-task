<?php

declare(strict_types=1);

namespace App\Tests;

use App\Palindrome;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

final class PalindromeTest extends TestCase
{
    public static function palindromeProvider(): array
    {
        // [текст, ожидание в обычном режиме, ожидание в strict-режиме]
        return [
            'простой кириллический палиндром'       => ['казак', true, true],
            'регистр учитывается только в strict'   => ['Казак', true, false],
            'фраза с пробелами'                     => ['А роза упала на лапу Азора', true, false],
            'буква ё с обеих сторон'                => ['Лёша на полке клопа нашёл', true, false],
            'латиница, пунктуация, апостроф'        => ["Madam, I'm Adam", true, false],
            'чётная длина, регистр'                 => ['Abba', true, false],
            'цифры'                                 => ['12321', true, true],
            'буквы и цифры вперемешку'              => ['1а2а1', true, true],
            'эмодзи (одна кодовая точка)'           => ['а😀а', true, true],
            'не палиндром'                          => ['привет', false, false],
            'не палиндром из цифр'                  => ['12345', false, false],
            'пустая строка — тривиальный палиндром' => ['', true, true],
            'один символ'                           => ['Ж', true, true],
            'пробелы в strict-режиме симметричны'   => ['   ', true, true],
        ];
    }

    #[DataProvider('palindromeProvider')]
    public function testIsPalindrome(string $text, bool $expected, bool $expectedStrict): void
    {
        self::assertSame($expected, Palindrome::isPalindrome($text));
        self::assertSame($expectedStrict, Palindrome::isPalindrome($text, strict: true));
    }

    public function testInvalidUtf8Throws(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        Palindrome::isPalindrome("\xB1\x31");
    }
}
