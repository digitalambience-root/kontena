
describe Stacks::Update do
  let(:grid) { Grid.create!(name: 'test-grid') }

  let(:stack) {
    Stacks::Create.run(
      grid: grid,
      name: 'stack',
      stack: 'foo/bar',
      version: '0.1.0',
      registry: 'file://',
      source: '...',
      services: [{name: 'redis', image: 'redis:2.8', stateful: true }]
    ).result
  }

  describe '#run' do
    it 'updates stack and creates a new revision' do
      services = [{name: 'redis', image: 'redis:3.0', stateful: true}]
      subject = described_class.new(
        stack_instance: stack,
        name: 'stack',
        stack: 'foo/bar',
        version: '0.1.0',
        registry: 'file://',
        source: '...',
        services: services
      )
      outcome = subject.run
      expect(outcome.success?).to be_truthy
      expect(outcome.result.stack_revisions.count).to eq(2)
      expect(stack.reload.grid_services.first.image_name).to eq('redis:2.8')
    end

    it 'does not increase version automatically' do
      services = [{name: 'redis', image: 'redis:3.0'}]
      subject = described_class.new(
        stack_instance: stack,
        stack: 'foo/bar',
        version: '0.1.0',
        registry: 'file://',
        source: '...',
        services: services
      )
      expect {
        outcome = subject.run
        expect(outcome.success?).to be_truthy
      }.not_to change{ stack.latest_rev.version }
    end

    it 'updates and creates new services' do
      services = [
        {name: 'redis', image: 'redis:3.0'},
        {name: 'foo', image: 'redis:3.0', stateful: true}
      ]
      subject = described_class.new(
        stack_instance: stack,
        stack: 'foo/bar',
        version: '0.1.0',
        registry: 'file://',
        source: '...',
        services: services
      )
      expect {
        outcome = subject.run
        expect(outcome.success?).to be_truthy
      }.to change{ stack.grid_services.count }.by(1)
    end

    it 'fails to create new volumes' do
      services = [
        {name: 'redis', image: 'redis:3.0', volumes: ['vol:/data']},
      ]
      volumes = [
        {name: 'vol', driver: 'local'}
      ]
      subject = described_class.new(
        stack_instance: stack,
        stack: 'foo/bar',
        version: '0.1.0',
        registry: 'file://',
        source: '...',
        services: services,
        volumes: volumes
      )
      expect {
        outcome = subject.run
        expect(outcome.success?).to be_falsey
      }.not_to change { [Volume.count, stack.latest_rev] }
    end
  end

  context "for a stack with externally linked services" do
    let(:stack) do
      Stacks::Create.run!(
        grid: grid,
        name: 'stack',
        stack: 'foo/bar',
        version: '0.1.0',
        registry: 'file://',
        source: '...',
        services: [
          {name: 'foo', image: 'redis', stateful: false },
          {name: 'bar', image: 'redis', stateful: false },
        ]
      )
    end

    let(:linking_service) do
      GridServices::Create.run!(
        grid: grid,
        stack: stack,
        name: 'asdf',
        image: 'redis',
        stateful: false,
        links: [
          {name: 'stack/bar', alias: 'bar'},
        ],
      )
    end

    it 'does not remove a linked service' do
      linking_service
      expect(stack.grid_services.find_by(name: 'bar').linked_from_services.to_a).to_not be_empty

      subject = described_class.new(
        stack_instance: stack,
        name: 'stack',
        stack: 'foo/bar',
        version: '0.1.0',
        registry: 'file://',
        source: '...',
        services: [
          {name: 'foo', image: 'redis', stateful: false },
        ],
      )

      expect{
        outcome = subject.run
        expect(outcome).to_not be_success
        expect(outcome.errors.message).to eq({'services' => {'bar' => { 'service' => 'Cannot delete service that is linked to another service (asdf)' } } })
      }.to not_change{stack.grid_services.count}
    end

    it 'does allow removing a linked service after removing the linking service' do
      linking_service.destroy
      expect(stack.grid_services.find_by(name: 'bar').linked_from_services.to_a).to be_empty

      subject = described_class.new(
        stack_instance: stack,
        name: 'stack',
        stack: 'foo/bar',
        version: '0.1.0',
        registry: 'file://',
        source: '...',
        services: [
          {name: 'foo', image: 'redis', stateful: false },
        ],
      )

      outcome = subject.run
      expect(outcome).to be_success
    end
  end
end
