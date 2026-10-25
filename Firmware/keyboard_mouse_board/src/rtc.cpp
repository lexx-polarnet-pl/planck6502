#include <Arduino.h>
#include <Wire.h>

#include <string.h>

#include "output.h"
#include "rtc.h"

namespace
{
constexpr uint8_t DS1307_ADDRESS = 0x68;
constexpr uint8_t DS1307_REGISTER_SECONDS = 0x00;
constexpr uint8_t DS1307_REGISTER_COUNT = 7;

const uint8_t ds1307_registers[] = {0x00, 0x01, 0x02, 0x04, 0x05, 0x06};

uint8_t to_bcd(uint8_t value)
{
    return ((value / 10) << 4) | (value % 10);
}

bool parse_two_digits(const char* value, uint8_t& result)
{
    if (value[0] < '0' || value[0] > '9'
        || value[1] < '0' || value[1] > '9')
    {
        return false;
    }

    result = (value[0] - '0') * 10 + (value[1] - '0');
    return true;
}

bool get_build_month(uint8_t& month)
{
    static const char month_names[][4] = {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    };

    for (uint8_t i = 0; i < 12; ++i)
    {
        if (strncmp(__DATE__, month_names[i], 3) == 0)
        {
            month = i + 1;
            return true;
        }
    }

    return false;
}

bool decode_bcd(uint8_t value, uint8_t maximum, uint8_t& decoded)
{
    const uint8_t ones = value & 0x0F;
    const uint8_t tens = (value >> 4) & 0x0F;
    if (ones > 9 || tens > 9)
    {
        return false;
    }

    decoded = tens * 10 + ones;
    return decoded <= maximum;
}

bool is_valid_date(uint8_t year, uint8_t month, uint8_t day)
{
    static const uint8_t days_in_month[] = {
        31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
    };

    if (month < 1 || month > 12)
    {
        return false;
    }

    uint8_t maximum_day = days_in_month[month - 1];
    if (month == 2 && year % 4 == 0)
    {
        maximum_day = 29;
    }

    return day >= 1 && day <= maximum_day;
}

bool decode_register_value(uint8_t register_offset, uint8_t raw, uint8_t& value)
{
    uint8_t decoded;
    switch (register_offset)
    {
        case 0:
            raw &= 0x7F;
            if (!decode_bcd(raw, 59, decoded)) return false;
            break;
        case 1:
            raw &= 0x7F;
            if (!decode_bcd(raw, 59, decoded)) return false;
            break;
        case 2:
            if (raw & 0x40)
            {
                uint8_t hour_12;
                if (!decode_bcd(raw & 0x1F, 12, hour_12) || hour_12 == 0)
                {
                    return false;
                }
                decoded = (hour_12 % 12) + ((raw & 0x20) ? 12 : 0);
            }
            else if (!decode_bcd(raw & 0x3F, 23, decoded))
            {
                return false;
            }
            break;
        case 3:
            raw &= 0x3F;
            if (!decode_bcd(raw, 31, decoded) || decoded == 0) return false;
            break;
        case 4:
            raw &= 0x1F;
            if (!decode_bcd(raw, 12, decoded) || decoded == 0) return false;
            break;
        case 5:
            if (!decode_bcd(raw, 99, decoded)) return false;
            break;
        default:
            return false;
    }

    value = to_bcd(decoded);
    return true;
}

bool validate_register_value(uint8_t register_offset, uint8_t value)
{
    uint8_t decoded;
    switch (register_offset)
    {
        case 0:
        case 1:
            return decode_bcd(value, 59, decoded);
        case 2:
            return decode_bcd(value, 23, decoded);
        case 3:
            return decode_bcd(value, 31, decoded) && decoded >= 1;
        case 4:
            return decode_bcd(value, 12, decoded) && decoded >= 1;
        case 5:
            return decode_bcd(value, 99, decoded);
        default:
            return false;
    }
}
}

void rtc_set_time_to_build_time()
{
    uint8_t month;
    uint8_t day;
    uint8_t hour;
    uint8_t minute;
    uint8_t second;
    uint8_t year;

    if (!get_build_month(month)
        || !parse_two_digits(__DATE__ + 4, day)
        || !parse_two_digits(__TIME__, hour)
        || !parse_two_digits(__TIME__ + 3, minute)
        || !parse_two_digits(__TIME__ + 6, second)
        || !parse_two_digits(__DATE__ + 9, year)
        || hour > 23 || minute > 59 || second > 59
        || !is_valid_date(year, month, day))
    {
        show_error("RTC: invalid build time\r\n");
        return;
    }

    Wire.begin();
    Wire.beginTransmission(DS1307_ADDRESS);
    Wire.write(DS1307_REGISTER_SECONDS);
    Wire.write(to_bcd(second)); // Writing seconds with CH=0 starts the oscillator.
    Wire.write(to_bcd(minute));
    Wire.write(to_bcd(hour));
    Wire.write(1); // Day of week (DS1307 accepts values 1-7).
    Wire.write(to_bcd(day));
    Wire.write(to_bcd(month));
    Wire.write(to_bcd(year));

    if (Wire.endTransmission() != 0)
    {
        show_error("RTC: set failed\r\n");
    }
}

void rtc_init()
{
    // On ATmega328P, Wire uses PC4 (SDA) and PC5 (SCL).
    Wire.begin();

    Wire.beginTransmission(DS1307_ADDRESS);
    Wire.write(DS1307_REGISTER_SECONDS);
    if (Wire.endTransmission(false) != 0)
    {
        show_error("RTC: no response\r\n");
        return;
    }

    if (Wire.requestFrom(DS1307_ADDRESS, DS1307_REGISTER_COUNT) != DS1307_REGISTER_COUNT)
    {
        show_error("RTC: read error\r\n");
        return;
    }

    uint8_t registers[DS1307_REGISTER_COUNT];
    for (uint8_t i = 0; i < DS1307_REGISTER_COUNT; ++i)
    {
        registers[i] = Wire.read();
    }

    if (registers[0] & 0x80)
    {
        show_error("RTC: clock stopped\r\n");
        return;
    }

    uint8_t second;
    uint8_t minute;
    uint8_t hour;
    uint8_t day;
    uint8_t month;
    uint8_t year;

    if (!decode_bcd(registers[0] & 0x7F, 59, second)
        || !decode_bcd(registers[1] & 0x7F, 59, minute))
    {
        show_error("RTC: invalid date/time\r\n");
        return;
    }

    const uint8_t raw_hour = registers[2];
    if (raw_hour & 0x40)
    {
        uint8_t hour_12;
        if (!decode_bcd(raw_hour & 0x1F, 12, hour_12) || hour_12 == 0)
        {
            show_error("RTC: invalid date/time\r\n");
            return;
        }
        hour = (hour_12 % 12) + ((raw_hour & 0x20) ? 12 : 0);
    }
    else if (!decode_bcd(raw_hour & 0x3F, 23, hour))
    {
        show_error("RTC: invalid date/time\r\n");
        return;
    }

    if (!decode_bcd(registers[4] & 0x3F, 31, day)
        || !decode_bcd(registers[5] & 0x1F, 12, month)
        || !decode_bcd(registers[6], 99, year)
        || !is_valid_date(year, month, day))
    {
        show_error("RTC: invalid date/time\r\n");
        return;
    }

    char message[32];
    snprintf(message, sizeof(message),
             "RTC: 20%02u-%02u-%02u %02u:%02u:%02u\r\n",
             static_cast<unsigned int>(year),
             static_cast<unsigned int>(month),
             static_cast<unsigned int>(day),
             static_cast<unsigned int>(hour),
             static_cast<unsigned int>(minute),
             static_cast<unsigned int>(second));
    show_message(message);
}

bool rtc_read_register(uint8_t register_offset, uint8_t& value)
{
    if (register_offset >= sizeof(ds1307_registers))
    {
        return false;
    }

    Wire.beginTransmission(DS1307_ADDRESS);
    Wire.write(ds1307_registers[register_offset]);
    if (Wire.endTransmission(false) != 0
        || Wire.requestFrom(DS1307_ADDRESS, static_cast<uint8_t>(1)) != 1)
    {
        show_error("RTC: read failed\r\n");
        return false;
    }

    const int raw = Wire.read();
    if (raw < 0 || !decode_register_value(register_offset, static_cast<uint8_t>(raw), value))
    {
        show_error("RTC: invalid register\r\n");
        return false;
    }

    return true;
}

bool rtc_write_register(uint8_t register_offset, uint8_t value)
{
    if (register_offset >= sizeof(ds1307_registers)
        || !validate_register_value(register_offset, value))
    {
        show_error("RTC: invalid register value\r\n");
        return false;
    }

    Wire.beginTransmission(DS1307_ADDRESS);
    Wire.write(ds1307_registers[register_offset]);
    Wire.write(value);
    if (Wire.endTransmission() != 0)
    {
        show_error("RTC: write failed\r\n");
        return false;
    }

    return true;
}
