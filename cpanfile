
requires 'perl', '5.18.0';
requires 'Feature::Compat::Try', '0.03';
requires 'Object::Pad', '0.60';
requires 'Scope::Guard', '0.21';

on test => sub {
    requires 'Future', '0.49';
    requires 'Future::Queue', '0.50';
    requires 'Test2::V0', '0.000147';
    requires 'Test2::Tools::Compare', '0.000147';
    requires 'Test2::Tools::Refcount', '0.000147';
};

on develop => sub {
    requires 'Dist::Zilla';
};
